#!/usr/bin/env python3
"""MATHCK optimization never weakens the runtime contract.

Folding: the codegen emits every check; LLVM may delete one only where it
proves the operation cannot overflow. In tests/fixtures/mathck/fold.pas the
FOR loops have constant bounds, so their `i + 1`, `i * 2 - 1` and `-i`
cannot leave INTEGER and the O1-O3 objects keep no failure call for them,
while the checks LLVM cannot bound (the accumulations into k and the
operations on the value read at run time) stay. The compiler adds no range
facts of its own: constant FOR bounds already reach LLVM's scalar
evolution, and a declared subrange is not a trustworthy fact (RANGECK-).

Whole-vector checks: a MATHCK+ integer VECTOR + - * or negation computes
every lane with one vector overflow intrinsic and branches once on the OR
of the overflow lanes; only the cold path redoes the operation lane by lane
to find the lowest failing lane (its diagnostics are pinned by
mathck_vector.py). The O0 IR must have that shape.

Runtime: fold.pas prints its exact output at O0-O3, and the same loop
ending at the INTEGER maximum still traps at the located operator.
"""
import re
import resource
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, ROOT, run

FIXTURE = ROOT / 'tests/fixtures/mathck/fold.pas'
EMITTED = 9  # checked operations in fold.pas, all emitted at O0
KEPT = 5  # three accumulations into k, n + 1 and s * n
RELOC = re.compile(r'R_X86_64_PLT32\s+pas_math_overflow')


def build(args):
    built = run(['bin/pascal1981'] + args)
    assert built.returncode == 0, (args, built.stderr)


def check_folding(work):
    ir = work / 'fold.ll'
    build(['-O0', '-S', str(FIXTURE), '-o', str(ir)])
    assert ir.read_text().count('call void @pas_math_overflow') == EMITTED
    expected = FIXTURE.with_suffix('.out').read_text()
    for opt in OPTS:
        exe = work / f'fold_O{opt}'
        build([f'-O{opt}', str(FIXTURE), '-o', str(exe)])
        result = run([str(exe)], input='3\n')
        assert (result.returncode, result.stdout,
                result.stderr) == (0, expected, ''), (opt, result)
        if opt == 0:
            continue
        obj = work / f'fold_O{opt}.o'
        build([f'-O{opt}', '-c', str(FIXTURE), '-o', str(obj)])
        dump = run(['objdump', '-dr', str(obj)])
        assert dump.returncode == 0, dump.stderr
        assert len(RELOC.findall(dump.stdout)) == KEPT, (opt, dump.stdout)
    return len(OPTS)


def check_bound_trap(work):
    """The folded loop's twin ending at 32767 overflows on its last step."""
    source = FIXTURE.read_text().replace('FOR i := 1 TO 32766 DO',
                                         'FOR i := 32760 TO 32767 DO')
    line = next(n for n, text in enumerate(source.splitlines(), 1)
                if 'FOR i := 32760' in text)
    col = source.splitlines()[line - 1].index('i + 1') + 3
    path = work / 'bound.pas'
    path.write_text(source)
    for opt in OPTS:
        exe = work / f'bound_O{opt}'
        build([f'-O{opt}', str(path), '-o', str(exe)])
        result = run([str(exe)], input='3\n')
        assert result.returncode != 0 and result.stdout == '', (opt, result)
        assert result.stderr == (
            'runtime error: MATHCK signed overflow in + at line '
            f'{line} column {col} (left=32767, right=1)\n'), (opt, result)
    return len(OPTS)


def check_vector_shape(work):
    cells = 0
    for elem, bits in [('INTEGER8', 8), ('INTEGER', 16), ('WORD32', 32),
                       ('INTEGER64', 64)]:
        path = work / f'vec_{elem}.pas'
        path.write_text('\n'.join([
            '{$MATHCK+}', 'PROGRAM vshape;', f'TYPE V = VECTOR [4] OF {elem};',
            'VAR a, b, c: V;', 'BEGIN',
            '  a := VSPLAT(1, V); b := VSPLAT(1, V);',
            '  c := a + b; c := a - b; c := a * b; c := -a', 'END.'
        ]) + '\n')
        ir = path.with_suffix('.ll')
        build(['--dialect', 'extended', '-O0', '-S', str(path), '-o', str(ir)])
        text = ir.read_text()
        sign = 'u' if elem.startswith('WORD') else 's'
        for op in ('add', 'sub', 'mul'):
            name = f'@llvm.{sign}{op}.with.overflow.v4i{bits}('
            want = 2 if op == 'sub' else 1  # negation is 0 - v
            assert text.count(f'call {{ <4 x i{bits}>, <4 x i1> }} {name}') \
                == want, (elem, op)
        anys = re.findall(
            r'(%vmath\.any\d*) = call i1 @llvm\.vector\.reduce\.or\.v4i1\(',
            text)
        assert len(anys) == 4, (elem, anys)
        for any_ in anys:
            assert re.search(
                r'br i1 ' + re.escape(any_) +
                r', label %vmath\.lanes\d*, label %vmath\.ok\d*', text), any_
        # The lane-by-lane failure paths exist only behind those branches.
        assert text.count('call void @pas_math_overflow') == 16, elem
        cells += 1
    return cells


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-opt-') as tmp:
        work = Path(tmp)
        folding = check_folding(work)
        trap = check_bound_trap(work)
        vector = check_vector_shape(work)
    print(f'PASS: MATHCK optimization: {folding} folding cells '
          f'({EMITTED} checks emitted, {KEPT} unprovable kept at O1-O3, '
          f'exact output); {trap} FOR-to-maximum trap cells; {vector} '
          'whole-vector check IR shapes (one overflow branch per operation, '
          'lane-by-lane only on the cold path)')


if __name__ == '__main__':
    main()
