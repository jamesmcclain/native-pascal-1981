#!/usr/bin/env python3
"""MATHCK for operands of different integer widths, and G24 admission.

Same-family operands of different widths widen to the wider operand, which
is the result type: the operation is checked (MATHCK+) or wraps (MATHCK-) at
that width, never at the narrower one. Oracles come from exact integer
arithmetic. A nonconstant INTEGER-family/WORD-family mixture is rejected at
every width, in either order, under either setting (docs/mathck_contract.md,
G24); constants keep their adaptation.
"""
import resource
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import (OPTS, SYMBOL, exact, limits, run, setup,
                             type_name, wrap)

WIDTHS = [8, 16, 32, 64]
OPS = ['PLUS', 'MINUS', 'MUL', 'DIV', 'MOD']
MIXED = 'Mixed INTEGER-family and WORD-family operands need an explicit conversion (e.g. WRD) in '


def samples(width, unsigned):
    low, high = limits(width, unsigned)
    values = {low, high, 0, 1, 2, 3, high // 2 + 1}
    if not unsigned:
        values |= {-1, -2, low // 2}
    return sorted(values)


def pair_rows(lw, rw, unsigned):
    """Ordered (op, left, right) rows split into fitting and overflowing."""
    width = max(lw, rw)
    low, high = limits(width, unsigned)
    fits, overflows = [], []
    for op in OPS:
        for left in samples(lw, unsigned):
            for right in samples(rw, unsigned):
                if op in ('DIV', 'MOD') and right == 0:
                    continue
                value = exact(op, left, right)
                (fits if low <= value <= high else overflows).append(
                    (op, left, right))
    return fits, overflows


def pair_program(lw, rw, unsigned, flag, rows):
    source = [
        f'{{$MATHCK{flag}}}', 'PROGRAM MixedWidth;',
        f'VAR gl: {type_name(lw, unsigned)}; gr: {type_name(rw, unsigned)};',
        'BEGIN'
    ]
    for op, left, right in rows:
        source += setup({'gl': left, 'gr': right})
        source.append(f'WRITELN(gl {SYMBOL[op]} gr);')
    source.append('END.')
    return '\n'.join(source) + '\n'


def pair_failure(lw, rw, unsigned, op, left, right):
    source = [
        '{$MATHCK+}', 'PROGRAM MixedWidthFailure;',
        f'VAR gl: {type_name(lw, unsigned)}; gr: {type_name(rw, unsigned)};',
        'BEGIN'
    ]
    source += setup({'gl': left, 'gr': right}) + ["WRITELN('prefix');"]
    call = f'  WRITELN(gl {SYMBOL[op]} gr);'
    column = call.index(SYMBOL[op], call.index('gl ')) + 1
    line = len(source) + 1
    source += [call, "  WRITELN('unreachable')", 'END.']
    sign = 'unsigned' if unsigned else 'signed'
    stderr = (f'runtime error: MATHCK {sign} overflow in {SYMBOL[op]} at line '
              f'{line} column {column} (left={left}, right={right})\n')
    return '\n'.join(source) + '\n', 'prefix\n', stderr


def first_per_op(rows):
    seen, out = set(), []
    for row in rows:
        if row[0] not in seen:
            seen.add(row[0])
            out.append(row)
    return out


def width_jobs():
    for unsigned in [False, True]:
        for lw in WIDTHS:
            for rw in WIDTHS:
                if lw == rw:
                    continue
                key = f'{lw}_{rw}_{int(unsigned)}'
                width = max(lw, rw)
                fits, overflows = pair_rows(lw, rw, unsigned)
                expected = ''.join(f'{exact(*row)}\n' for row in fits)
                for flag in ['+', '-']:
                    source = pair_program(lw, rw, unsigned, flag, fits)
                    for opt in OPTS:
                        yield (f'ok_{key}_{flag == "+"}', source, opt,
                               (0, expected, ''))
                expected = ''.join(f'{wrap(exact(*row), width, unsigned)}\n'
                                   for row in overflows)
                source = pair_program(lw, rw, unsigned, '-', overflows)
                for opt in OPTS:
                    yield f'wrap_{key}', source, opt, (0, expected, '')
                for index, row in enumerate(first_per_op(overflows)):
                    source, stdout, stderr = pair_failure(
                        lw, rw, unsigned, *row)
                    # One overflow per operator; O0/O2 keep the run time down.
                    for opt in (0, 2):
                        yield (f'fail_{key}_{index}', source, opt,
                               (None, stdout, stderr))


# The punchlist case: INTEGER32 * INTEGER is checked at 32 bits. 2000000000
# exceeds INTEGER but fits INTEGER32; 2147483647 * 2 does not fit either.
FAIL_LINE = '  a := 2147483647; i := 2; WRITELN(a * i)'
NAMED = [
    ('int32_times_int', '{$MATHCK+}\nPROGRAM Named;\n'
     'VAR a: INTEGER32; i: INTEGER;\nBEGIN\n'
     '  a := 100000; i := 20000; WRITELN(a * i); WRITELN(i * a);\n'
     '  a := 2147483647; i := 1; WRITELN(a - i + i)\nEND.\n',
     (0, '2000000000\n2000000000\n2147483647\n', '')),
    ('int32_times_int_fail', '{$MATHCK+}\nPROGRAM Named;\n'
     'VAR a: INTEGER32; i: INTEGER;\nBEGIN\n' + FAIL_LINE + '\nEND.\n',
     (None, '', 'runtime error: MATHCK signed overflow in * at line 5 '
      f'column {FAIL_LINE.index("*") + 1} (left=2147483647, right=2)\n')),
]


def check(work, job):
    tag, source, opt, (code, stdout, stderr) = job
    path = work / f'{tag}_O{opt}.pas'
    exe = work / f'{tag}_O{opt}'
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', 'extended', f'-O{opt}',
        str(path), '-o',
        str(exe)
    ])
    assert built.returncode == 0, (path, built.stderr)
    result = run([str(exe)])
    if code is None:
        assert result.returncode != 0, (path, result)
    else:
        assert result.returncode == code, (path, result)
    assert (result.stdout, result.stderr) == (stdout, stderr), (path, opt,
                                                                result)


def admission_jobs():
    """Every signed/unsigned width pair, both orders, all operators."""
    pairs = [('vintage', 16, 16)]
    pairs += [('extended', sw, uw) for sw in WIDTHS for uw in WIDTHS]
    for dialect, sw, uw in pairs:
        for op in OPS:
            for signed_left in [True, False]:
                for flag in ['+', '-']:
                    yield dialect, sw, uw, op, signed_left, flag


def check_admission(work, job):
    dialect, sw, uw, op, signed_left, flag = job
    left, right = ('s', 'u') if signed_left else ('u', 's')
    tag = f'adm_{dialect}_{sw}_{uw}_{op}_{int(signed_left)}_{flag == "+"}'
    path = work / f'{tag}.pas'
    path.write_text(
        f'{{$MATHCK{flag}}}\nPROGRAM Admission;\n'
        f'VAR s: {type_name(sw, False)}; u: {type_name(uw, True)};\n'
        f'BEGIN\n  s := 3; u := 5;\n  WRITELN({left} {SYMBOL[op]} {right})\n'
        'END.\n')
    ir = work / f'{tag}.ll'
    built = run([
        'bin/pascal1981', '--dialect', dialect, '-O0', '-S',
        str(path), '-o',
        str(ir)
    ])
    assert built.returncode != 0, (job, 'mixed operands accepted')
    assert f'{MIXED}{SYMBOL[op]}\n' in built.stderr, (job, built.stderr)
    assert not ir.exists() or ir.stat().st_size == 0, (job, 'IR published')


def constant_prologue(dialect):
    wide = ' a: INTEGER32; d: WORD32;' if dialect == 'extended' else ''
    init = ' a := 5; d := 5;' if dialect == 'extended' else ''
    return ('PROGRAM Adapt;\nCONST NEG = -1; BIG = 40000;\n'
            f'VAR w: WORD; i: INTEGER;{wide}\n'
            f'BEGIN\n  w := 5; i := -2;{init}\n')


# (dialect, flag, statement, expected stdout or None for a G24 rejection).
# An INTEGER constant adapts to a WORD operand by its bit pattern, so the
# adapted unsigned arithmetic wraps under MATHCK- (IBM 8-4: WRD(C) + -1
# overflows). A WORD constant adapts to a signed operand only if it fits.
CONSTANT_CASES = [
    ('vintage', '-', 'WRITELN(w + (-1), w - NEG, NEG + w)', '464\n'),
    ('vintage', '-', 'WRITELN(w + WRD(i), WRD(i) - w)', '365529\n'),
    ('vintage', '+', 'WRITELN(i + 30000, w + 30000)', '2999830005\n'),
    ('extended', '+', 'WRITELN(a + 40000, 40000 * a, a - BIG)',
     '40005200000-39995\n'),
    ('extended', '-', 'WRITELN(d - NEG, d + (-1))', '64\n'),
    ('vintage', '+', 'WRITELN(i + BIG)', None),
    ('vintage', '+', 'WRITELN(40000 - i)', None),
]


def check_constants(work):
    for index, (dialect, flag, statement, stdout) in enumerate(CONSTANT_CASES):
        path = work / f'const_{index}.pas'
        exe = work / f'const_{index}'
        source = (f'{{$MATHCK{flag}}}\n{constant_prologue(dialect)}'
                  f'  {statement}\nEND.\n')
        path.write_text(source)
        built = run([
            'bin/pascal1981', '--dialect', dialect, '-O0',
            str(path), '-o',
            str(exe)
        ])
        if stdout is None:
            assert built.returncode != 0 and MIXED in built.stderr, (
                source, built.stderr)
            continue
        assert built.returncode == 0, (source, built.stderr)
        result = run([str(exe)])
        assert (result.returncode, result.stdout,
                result.stderr) == (0, stdout, ''), (source, result)
    return len(CONSTANT_CASES)


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-mixed-') as tmp:
        work = Path(tmp)
        todo = list(width_jobs())
        todo += [(tag, source, opt, want) for tag, source, want in NAMED
                 for opt in OPTS]
        admissions = list(admission_jobs())
        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(lambda job: check(work, job), todo))
            list(pool.map(lambda job: check_admission(work, job), admissions))
        constants = check_constants(work)
    print(f'PASS: MATHCK mixed widths: {len(todo)} runtime cells (wider '
          f'operand sets the checked/wrapped width, O0-O3); {len(admissions)} '
          f'G24 rejections with no IR; {constants} constant-adaptation cells')


if __name__ == '__main__':
    main()
