#!/usr/bin/env python3
"""MATHCK for integer VECTOR lanes and the VSUM/VPROD reductions.

Every integer element type, extended dialect, O0-O3. Lane `+ - *` and
negation are checked per lane under MATHCK+ (the lowest failing lane reports
its own operands) and wrap under MATHCK-. Lane DIV/MOD have the scalar
mandatory zero-divisor failure and safe MIN/-1 under either setting. VSUM and
VPROD fold left to right, each step checked under MATHCK+, and wrap under
MATHCK-. Oracles come from exact integer arithmetic.
"""
import re
import resource
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, SYMBOL, exact, limits, run, type_name, wrap

WIDTHS = [8, 16, 32, 64]
LANES = 4


def assign(name, value):
    """Give a scalar its value at run time (64-bit extremes from halves)."""
    if abs(value) <= 1 << 53:
        return [f'{name} := {value};']
    return [
        f'{name} := {value >> 32};', f'{name} := {name} * 4294967296;',
        f'{name} := {name} + {value & 0xFFFFFFFF};'
    ]


def vector_setup(vec, values):
    out = []
    for lane, value in enumerate(values):
        out += assign('t', value) + [f'{vec}[{lane}] := t;']
    return out


def prologue(width, unsigned, flag):
    tk = type_name(width, unsigned)
    return [
        f'{{$MATHCK{flag}}}', 'PROGRAM VectorMath;',
        f'TYPE V = VECTOR [{LANES}] OF {tk};', f'VAR a, b, c: V; t, s: {tk};',
        'BEGIN'
    ]


def lanes_out(vec):
    return [f'WRITELN({vec}[{lane}]);' for lane in range(LANES)]


def binary_rows(width, unsigned):
    """(op, left lanes, right lanes); the overflowing lane is lane 2 and
    lane 3 overflows too, so the report must name lane 2's operands."""
    low, high = limits(width, unsigned)
    if unsigned:
        return [('PLUS', [1, high - 1, high, high], [2, 1, 1, 2]),
                ('MINUS', [5, high, 0, 1], [5, high, 1, 2]),
                ('MUL', [3, 1, high, high], [5, high, 2, 3])]
    return [('PLUS', [low, high - 1, high, low], [high, 1, 1, -1]),
            ('MINUS', [high, low + 1, low, high], [high, 1, 1, -1]),
            ('MUL', [-1, low // 2, high, low], [high, 2, 2, -1])]


def binary_job(width, unsigned, op, left, right, flag):
    source = prologue(width, unsigned, flag) + vector_setup('a', left)
    source += vector_setup('b', right) + ["WRITELN('prefix');"]
    call = f'  c := a {SYMBOL[op]} b;'
    line = len(source) + 1
    column = call.index(SYMBOL[op]) + 1
    source += [call] + lanes_out('c') + ['END.']
    results = [exact(op, l, r) for l, r in zip(left, right)]
    if flag == '-':
        stdout = 'prefix\n' + ''.join(f'{wrap(v, width, unsigned)}\n'
                                      for v in results)
        return '\n'.join(source) + '\n', (0, stdout, '')
    sign = 'unsigned' if unsigned else 'signed'
    stderr = (f'runtime error: MATHCK {sign} overflow in {SYMBOL[op]} at line '
              f'{line} column {column} (left={left[2]}, right={right[2]})\n')
    return '\n'.join(source) + '\n', (None, 'prefix\n', stderr)


def success_job(width, unsigned, flag):
    """Boundary lanes that fit print exactly under either setting."""
    low, high = limits(width, unsigned)
    if unsigned:
        rows = [('PLUS', [high - 1, 0, 1, 2], [1, 0, high - 1, 3]),
                ('MINUS', [high, 1, 9, high], [high, 0, 4, 1]),
                ('MUL', [high, 1, 2, 0], [1, high, high // 2, high]),
                ('DIV', [high, 9, 0, high], [1, 2, 7, high]),
                ('MOD', [high, 9, 0, high], [2, 4, 7, high])]
    else:
        rows = [('PLUS', [low, high, -1, low + 1], [0, 0, 1, high]),
                ('MINUS', [low + 1, -1, high, 0], [1, high, high, high]),
                ('MUL', [low // 2, -1, high, low], [2, high, -1, 1]),
                ('DIV', [low, -7, 7, high], [1, 2, -2, -1]),
                ('MOD', [low, -7, 7, high], [3, 2, -2, -1])]
    source = prologue(width, unsigned, flag)
    expected = []
    for op, left, right in rows:
        source += vector_setup('a', left) + vector_setup('b', right)
        source += [f'c := a {SYMBOL[op]} b;'] + lanes_out('c')
        expected += [exact(op, l, r) for l, r in zip(left, right)]
    if not unsigned:
        lanes = [high, 0, -high, low + 1]
        source += vector_setup('a', lanes) + ['c := -a;'] + lanes_out('c')
        expected += [-v for v in lanes]
    source.append('END.')
    return '\n'.join(source) + '\n', (0, ''.join(f'{v}\n'
                                                 for v in expected), '')


def negate_job(width, unsigned, flag):
    low, high = limits(width, unsigned)
    lanes = [0, 0, 1, 1] if unsigned else [high, 0, low, low]
    source = prologue(width, unsigned, flag) + vector_setup('a', lanes)
    source += ["WRITELN('prefix');"]
    call = '  c := -a;'
    line = len(source) + 1
    source += [call] + lanes_out('c') + ['END.']
    if flag == '-':
        stdout = 'prefix\n' + ''.join(f'{wrap(-v, width, unsigned)}\n'
                                      for v in lanes)
        return '\n'.join(source) + '\n', (0, stdout, '')
    sign = 'unsigned' if unsigned else 'signed'
    stderr = (f'runtime error: MATHCK {sign} overflow in - at line {line} '
              f'column {call.index("-") + 1} (operand={lanes[2]})\n')
    return '\n'.join(source) + '\n', (None, 'prefix\n', stderr)


def divmod_jobs(width, unsigned, flag):
    """A zero lane fails under either setting; signed MIN/-1 is MIN (DIV,
    MATHCK-), an overflow (DIV, MATHCK+) or 0 (MOD)."""
    low, high = limits(width, unsigned)
    sign = 'unsigned' if unsigned else 'signed'
    for op in ['DIV', 'MOD']:
        left, right = [high, 7, 9, high], [1, 2, 0, 0]
        source = prologue(width, unsigned, flag) + vector_setup('a', left)
        source += vector_setup('b', right) + ["WRITELN('prefix');"]
        call = f'  c := a {op} b;'
        line = len(source) + 1
        source += [call] + lanes_out('c') + ['END.']
        stderr = (f'runtime error: MATHCK {sign} division by zero in {op} at '
                  f'line {line} column {call.index(op) + 1} '
                  f'(left=9, right=0)\n')
        yield f'zero_{op}', '\n'.join(source) + '\n', (None, 'prefix\n',
                                                       stderr)
        if unsigned:
            continue
        left, right = [7, low, low, 1], [2, -1, -1, 1]
        source = prologue(width, unsigned, flag) + vector_setup('a', left)
        source += vector_setup('b', right) + ["WRITELN('prefix');"]
        call = f'  c := a {op} b;'
        line = len(source) + 1
        source += [call] + lanes_out('c') + ['END.']
        if op == 'DIV' and flag == '+':
            stderr = (f'runtime error: MATHCK signed overflow in DIV at line '
                      f'{line} column {call.index(op) + 1} '
                      f'(left={low}, right=-1)\n')
            want = (None, 'prefix\n', stderr)
        else:
            values = [3, low, low, 1] if op == 'DIV' else [1, 0, 0, 0]
            want = (0, 'prefix\n' + ''.join(f'{v}\n' for v in values), '')
        yield f'minus1_{op}', '\n'.join(source) + '\n', want


def reduce_jobs(width, unsigned, flag):
    low, high = limits(width, unsigned)
    sign = 'unsigned' if unsigned else 'signed'
    for name, op in [('VSUM', 'PLUS'), ('VPROD', 'MUL')]:
        if name == 'VSUM':
            fits = [high - 3, 1, 1, 1] if unsigned else [low, high, -1, 1]
            lanes = [high - 1, 1, 1, 0]
        else:
            fits = [1, 2, high // 4, 1] if unsigned else [-1, high, 1, -1]
            lanes = [high // 2 + 1, 1, 2, 0]
        expected, partial = fits[0], fits[0]
        for v in fits[1:]:
            expected = exact(op, expected, v)
        source = prologue(width, unsigned, flag) + vector_setup('a', fits)
        source += [f'WRITELN({name}(a));']
        source += vector_setup('a', lanes) + ["WRITELN('prefix');"]
        call = f'  s := {name}(a); WRITELN(s);'
        line = len(source) + 1
        source += [call, 'END.']
        # The fold fails at the first step whose exact result does not fit.
        partial, failure = lanes[0], None
        for v in lanes[1:]:
            value = exact(op, partial, v)
            if not low <= value <= high and failure is None:
                failure = (partial, v)
            partial = wrap(value, width, unsigned)
        assert failure, (name, width, unsigned)
        if flag == '-':
            want = (0, f'{expected}\nprefix\n{partial}\n', '')
        else:
            stderr = (f'runtime error: MATHCK {sign} overflow in {name} at '
                      f'line {line} column {call.index(name) + 1} '
                      f'(left={failure[0]}, right={failure[1]})\n')
            want = (None, f'{expected}\nprefix\n', stderr)
        yield f'reduce_{name}', '\n'.join(source) + '\n', want


def jobs():
    for width in WIDTHS:
        for unsigned in [False, True]:
            key = f'{width}_{int(unsigned)}'
            for flag in ['+', '-']:
                tag = f'{key}_{flag == "+"}'
                cells = [(f'ok_{tag}', *success_job(width, unsigned, flag)),
                         (f'neg_{tag}', *negate_job(width, unsigned, flag))]
                for op, left, right in binary_rows(width, unsigned):
                    cells.append(
                        (f'{op}_{tag}',
                         *binary_job(width, unsigned, op, left, right, flag)))
                for name, source, want in divmod_jobs(width, unsigned, flag):
                    cells.append((f'{name}_{tag}', source, want))
                for name, source, want in reduce_jobs(width, unsigned, flag):
                    cells.append((f'{name}_{tag}', source, want))
                for name, source, want in cells:
                    for opt in OPTS:
                        yield name, source, opt, want


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
    assert (result.stdout, result.stderr) == (stdout, stderr), (path, result)


def check_ir(work):
    """MATHCK- lane + - * keep the vector instruction with no overflow
    intrinsic; DIV/MOD never reach a vector division instruction."""
    source = '\n'.join(
        prologue(16, False, '-') + [
            'c := a + b; c := a - b; c := a * b; c := -a; t := VSUM(a);',
            'c := a DIV b; c := a MOD b;', 'END.'
        ]) + '\n'
    path = work / 'ir.pas'
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', 'extended', '-O0', '-S',
        str(path), '-o',
        str(work / 'ir.ll')
    ])
    assert built.returncode == 0, built.stderr
    ir = (work / 'ir.ll').read_text()
    assert 'with.overflow' not in ir and 'pas_math_overflow' not in ir, ir
    for inst in [
            'add <4 x i16>', 'sub <4 x i16>', 'mul <4 x i16>',
            'llvm.vector.reduce.add'
    ]:
        assert inst in ir, inst
    assert not re.search(r'= s(div|rem) <', ir), 'vector division emitted'
    assert ir.count('call void @pas_math_zero') == 8, ir
    return 1


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-vector-') as tmp:
        work = Path(tmp)
        todo = list(jobs())
        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(lambda job: check(work, job), todo))
        check_ir(work)
    print(f'PASS: MATHCK VECTOR lanes and VSUM/VPROD: {len(todo)} runtime '
          'cells (every integer element type, both settings, O0-O3); '
          'MATHCK- IR keeps vector + - * and has no vector division')


if __name__ == '__main__':
    main()
