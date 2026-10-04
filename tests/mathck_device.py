#!/usr/bin/env python3
"""MATHCK in DEVICE code.

NVPTX has no host failure path, so an operation MATHCK+ would check is a hard
compile-time `MATHCK unsupported boundary: DEVICE arithmetic at line L column
C` with no IR published (docs/mathck_contract.md); MATHCK- at the operation
is the opt-out. Operations MATHCK does not check (fully constant folds, WORD
ABS, REAL arithmetic, TRUNC) are not boundaries. CPU DEVICE code shares the
host failure path, so its kernels trap (MATHCK+) or wrap (MATHCK-) exactly
like host code, through LAUNCH.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import ROOT

BOUNDARY = 'MATHCK unsupported boundary: DEVICE arithmetic'
# (statement, token marking the operation's column). Each uses a variable
# operand so nothing folds.
CHECKED = [('i := k + 1', '+'), ('i := k - 1', '-'), ('i := k * 2', '*'),
           ('i := -k', '-'),
           ('i := SUCC(k)', 'SUCC'), ('i := PRED(k)', 'PRED'),
           ('i := ABS(k)', 'ABS'), ('i := SQR(k)', 'SQR'), ('d := e + 1', '+'),
           ('d := e * e', '*'), ('w := v + 1', '+'), ('w := SQR(v)', 'SQR'),
           ('i := k DIV 2', 'DIV'), ('i := k MOD 2', 'MOD')]
UNCHECKED = [
    'i := 3 + 4', 'w := ABS(v)', 'r := r * 2.0 + 1.0', 'i := TRUNC(r)',
    'i := k', 'i := ORD(c)'
]


def module(statement, flag):
    return (
        'DEVICE MODULE DevMath;\n'
        'VAR k, i: INTEGER; d, e: INTEGER32; v, w: WORD; r: REAL; c: CHAR;\n'
        f'{{$MATHCK{flag}}}\n'
        'PROCEDURE work;\n'
        'BEGIN\n'
        f'  {statement}\n'
        'END;\n'
        '.\n')


def compile_nvptx(work, name, source):
    path = work / f'{name}.pas'
    ir = work / f'{name}.ll'
    path.write_text(source)
    result = subprocess.run([
        str(ROOT / 'bin/pascal1981'), '--dialect', 'extended',
        '--device-triple', 'nvptx64-nvidia-cuda', '-S',
        str(path), '-o',
        str(ir)
    ],
                            cwd=work,
                            text=True,
                            capture_output=True,
                            timeout=60)
    return result, ir


def check_nvptx(work):
    cells = 0
    for index, (statement, token) in enumerate(CHECKED):
        result, ir = compile_nvptx(work, f'on{index}', module(statement, '+'))
        line = f'  {statement}'
        column = line.index(token, line.index(':=')) + 1
        want = f'{BOUNDARY} at line 6 column {column}\n'
        assert result.returncode != 0, (statement, 'accepted')
        assert result.stderr == want, (statement, result.stderr)
        assert not ir.exists() or ir.stat().st_size == 0, (statement, 'IR')
        cells += 1
        result, ir = compile_nvptx(work, f'off{index}', module(statement, '-'))
        if token in ('DIV', 'MOD'):
            # MATHCK- does not waive the mandatory zero-divisor safety.
            assert result.returncode != 0, statement
            assert 'scalar DIV/MOD safety is unsupported on DEVICE' in \
                result.stderr, (statement, result.stderr)
        else:
            assert result.returncode == 0, (statement, result.stderr)
            text = ir.read_text()
            assert 'with.overflow' not in text and 'pas_math' not in text, text
        cells += 1
    for index, statement in enumerate(UNCHECKED):
        result, ir = compile_nvptx(work, f'free{index}',
                                   module(statement, '+'))
        assert result.returncode == 0, (statement, result.stderr)
        cells += 1
    # The setting is per operation: a MATHCK- statement inside MATHCK+ code.
    source = module('{$MATHCK-} i := k + 1 {$MATHCK+}; i := 5', '+')
    result, _ = compile_nvptx(work, 'scoped', source)
    assert result.returncode == 0, result.stderr
    source = module('{$MATHCK-} i := k + 1; {$MATHCK+} i := i * 3', '+')
    result, _ = compile_nvptx(work, 'scoped2', source)
    column = '  {$MATHCK-} i := k + 1; {$MATHCK+} i := i * 3'.rindex('*') + 1
    assert result.stderr == f'{BOUNDARY} at line 6 column {column}\n', \
        result.stderr
    return cells + 2


INTERFACE = """DEVICE INTERFACE;
UNIT BUMPU (BUMP);
PROCEDURE BUMP(cell: ADS(GLOBAL) OF INTEGER32);
END;
"""


def impl(flag):
    return f"""(*$INCLUDE:'bump.inc'*)
{{$MATHCK{flag}}}
DEVICE IMPLEMENTATION OF BUMPU;
PROCEDURE BUMP(cell: ADS(GLOBAL) OF INTEGER32);
BEGIN
  cell^ := cell^ + 1
END;
.
"""


HOST = """(*$INCLUDE:'bump.inc'*)
PROGRAM BUMPMAIN(output);
USES BUMPU (BUMP);
TYPE PINT = ^INTEGER32;
VAR cell: PINT;
BEGIN
  NEW(cell); cell^ := 2147483646;
  LAUNCH(BUMP, 1, 1, cell);
  WRITELN(cell^);
  LAUNCH(BUMP, 1, 1, cell);
  WRITELN(cell^)
END.
"""


def check_cpu_device(work):
    (work / 'bump.inc').write_text(INTERFACE)
    (work / 'main.pas').write_text(HOST)
    column = '  cell^ := cell^ + 1'.index('+') + 1
    expected = {
        '+': (False, '2147483647\n',
              'runtime error: MATHCK signed overflow in + at line 6 column '
              f'{column} (left=2147483647, right=1)\n'),
        '-': (True, '2147483647\n-2147483648\n', '')
    }
    cells = 0
    for flag, (ok, stdout, stderr) in expected.items():
        (work / 'bump.impl').write_text(impl(flag))
        for opt in (0, 2):
            exe = work / f'bump_{flag == "+"}_O{opt}'
            built = subprocess.run([
                str(ROOT / 'bin/pascal1981'), '--dialect', 'extended',
                f'-O{opt}', 'main.pas', 'bump.impl', '-o',
                str(exe)
            ],
                                   cwd=work,
                                   text=True,
                                   capture_output=True,
                                   timeout=60)
            assert built.returncode == 0, built.stderr
            result = subprocess.run([str(exe)],
                                    cwd=work,
                                    text=True,
                                    capture_output=True,
                                    timeout=60)
            assert (result.returncode == 0) == ok, result
            assert (result.stdout, result.stderr) == (stdout, stderr), result
            cells += 1
    return cells


def main():
    with tempfile.TemporaryDirectory(prefix='mathck-device-') as tmp:
        work = Path(tmp)
        nvptx = check_nvptx(work)
        cpu = check_cpu_device(work)
    print(f'PASS: MATHCK DEVICE: {nvptx} NVPTX cells (enabled checked '
          'operations are located unsupported boundaries with no IR; '
          'MATHCK- and unchecked operations compile); '
          f'{cpu} CPU DEVICE cells trap or wrap through LAUNCH')


if __name__ == '__main__':
    main()
