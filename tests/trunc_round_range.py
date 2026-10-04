#!/usr/bin/env python3
"""TRUNC/ROUND INTEGER range check (G26): always on, independent of MATHCK.

IBM 11-6: "Error if ABS(X) > MAXINT". A result outside -32768..32767, or a
NaN argument, fails with one located `runtime error:` line after flushing
stdout, under {$MATHCK+} and {$MATHCK-} alike, both dialects, O0-O3. CPU
DEVICE code takes the same host failure path; NVPTX code has no host failure
path and saturates (llvm.fptosi.sat) instead of producing LLVM poison.
"""
import resource
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, ROOT, run

# (expression, printed value) pairs that fit INTEGER, including the extremes
# and ROUND's half-away-from-zero ties.
VALID = [('TRUNC(r + 32767.9)', 32767), ('TRUNC(r - 32768.9)', -32768),
         ('TRUNC(r - 0.5)', 0), ('TRUNC(r + 7.99)', 7),
         ('ROUND(r + 32767.4)', 32767), ('ROUND(r - 32768.4)', -32768),
         ('ROUND(r + 2.5)', 3), ('ROUND(r - 2.5)', -3), ('ROUND(r + 0.4)', 0),
         ('ROUND(r - 0.5)', -1)]
# (function, argument expression, value as reported).
INVALID = [('TRUNC', 'r + 32768.0', '32768'),
           ('TRUNC', 'r - 32769.0', '-32769'),
           ('TRUNC', 'r + 1.0E300', '1.0000000000000001e+300'),
           ('TRUNC', 'z / z', 'NaN'), ('ROUND', 'r + 32767.5', '32767.5'),
           ('ROUND', 'r - 32768.5', '-32768.5'),
           ('ROUND', 'r - 1.0E300', '-1.0000000000000001e+300'),
           ('ROUND', 'z / z', 'NaN')]
PROLOGUE = [
    'PROGRAM Conversion(output);', 'VAR r, z: REAL; i: INTEGER;', 'BEGIN',
    '  r := 0.0; z := 0.0;'
]


def valid_job(flag):
    source = [f'{{$MATHCK{flag}}}'] + PROLOGUE
    source += [f'  i := {expr}; WRITELN(i);' for expr, _ in VALID]
    source.append('END.')
    return '\n'.join(source) + '\n', (0, ''.join(f'{v}\n'
                                                 for _, v in VALID), '')


def invalid_job(flag, name, arg, shown):
    source = [f'{{$MATHCK{flag}}}'] + PROLOGUE + ["  WRITELN('prefix');"]
    call = f'  i := {name}({arg}); WRITELN(i)'
    line = len(source) + 1
    source += [call, 'END.']
    stderr = (f'runtime error: {name} result out of INTEGER range at line '
              f'{line} column {call.index(name) + 1} (value={shown})\n')
    return '\n'.join(source) + '\n', (None, 'prefix\n', stderr)


def real32_job():
    """A REAL32 argument widens first and is checked the same way."""
    source = [
        'PROGRAM Conversion32(output);', 'VAR s: REAL32; i: INTEGER;', 'BEGIN',
        '  s := 40000.0;', "  WRITELN('prefix');"
    ]
    call = '  i := TRUNC(s); WRITELN(i)'
    line = len(source) + 1
    source += [call, 'END.']
    stderr = ('runtime error: TRUNC result out of INTEGER range at line '
              f'{line} column {call.index("TRUNC") + 1} (value=40000)\n')
    return '\n'.join(source) + '\n', (None, 'prefix\n', stderr)


def jobs():
    for dialect in ['vintage', 'extended']:
        for flag in ['+', '-']:
            cells = [('valid', *valid_job(flag))]
            for index, row in enumerate(INVALID):
                cells.append((f'bad{index}', *invalid_job(flag, *row)))
            if dialect == 'extended':
                cells.append(('real32', *real32_job()))
            for tag, source, want in cells:
                for opt in OPTS:
                    yield (f'{tag}_{dialect}_{flag == "+"}', source, dialect,
                           opt, want)


def check(work, job):
    tag, source, dialect, opt, (code, stdout, stderr) = job
    path = work / f'{tag}_O{opt}.pas'
    exe = work / f'{tag}_O{opt}'
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', dialect, f'-O{opt}',
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


DEVICE_INTERFACE = """DEVICE INTERFACE;
UNIT CONVU (CONV);
PROCEDURE CONV(x: ADS(GLOBAL) OF REAL; cell: ADS(GLOBAL) OF INTEGER32);
END;
"""
# The kernel's `+` would be a MATHCK DEVICE boundary on NVPTX; the
# conversion check under test is independent of MATHCK.
DEVICE_IMPL = """(*$INCLUDE:'conv.inc'*)
DEVICE IMPLEMENTATION OF CONVU; {$MATHCK-}
PROCEDURE CONV(x: ADS(GLOBAL) OF REAL; cell: ADS(GLOBAL) OF INTEGER32);
BEGIN
  cell^ := TRUNC(x^) + ROUND(x^)
END;
.
"""


def device_host(value):
    return f"""(*$INCLUDE:'conv.inc'*)
PROGRAM CONVMAIN(output);
USES CONVU (CONV);
TYPE PINT = ^INTEGER32; PREAL = ^REAL;
VAR cell: PINT; x: PREAL;
BEGIN
  NEW(cell); NEW(x); cell^ := 0; x^ := {value};
  WRITELN('prefix');
  LAUNCH(CONV, 1, 1, x, cell);
  WRITELN(cell^)
END.
"""


def check_device(work):
    """CPU DEVICE fails on the host path; NVPTX saturates, never poison."""
    (work / 'conv.inc').write_text(DEVICE_INTERFACE)
    (work / 'conv.impl').write_text(DEVICE_IMPL)
    cells = 0
    for value, want in [('1234.6', (0, 'prefix\n2469\n', '')),
                        ('100000.0',
                         (None, 'prefix\n',
                          ('runtime error: TRUNC result out of INTEGER range '
                           'at line 5 column 12 (value=100000)\n')))]:
        (work / 'main.pas').write_text(device_host(value))
        for opt in (0, 2):
            exe = work / f'devhost_O{opt}'
            built = subprocess_run(work, [
                str(ROOT / 'bin/pascal1981'), '--dialect', 'extended',
                f'-O{opt}', 'main.pas', 'conv.impl', '-o',
                str(exe)
            ])
            assert built.returncode == 0, built.stderr
            result = subprocess_run(work, [str(exe)])
            code, stdout, stderr = want
            assert (code is None) == (result.returncode != 0), result
            assert (result.stdout, result.stderr) == (stdout, stderr), result
            cells += 1
    for opt in (0, 2):
        ir = work / f'nvptx_O{opt}.ll'
        built = subprocess_run(work, [
            str(ROOT / 'bin/pascal1981'), '--dialect', 'extended', f'-O{opt}',
            '--device-triple', 'nvptx64-nvidia-cuda', '-S', 'conv.impl', '-o',
            str(ir)
        ])
        assert built.returncode == 0, built.stderr
        text = ir.read_text()
        assert text.count('call i16 @llvm.fptosi.sat.i16.f64') == 2, text
        assert 'fptosi double' not in text, text
        assert 'pas_conversion_error' not in text, text
        cells += 1
    return cells


def subprocess_run(cwd, cmd):
    return subprocess.run(cmd,
                          cwd=cwd,
                          text=True,
                          capture_output=True,
                          timeout=60)


def check_ir(work):
    """The range test precedes the conversion: fptosi only in conv.ok."""
    path = work / 'ir.pas'
    path.write_text('PROGRAM Ir(output);\nVAR r: REAL; i: INTEGER;\n'
                    'BEGIN\n  r := 1.5; i := TRUNC(r); i := ROUND(r)\nEND.\n')
    built = run(
        ['bin/pascal1981', '-O0', '-S',
         str(path), '-o',
         str(work / 'ir.ll')])
    assert built.returncode == 0, built.stderr
    text = (work / 'ir.ll').read_text()
    assert text.count('call void @pas_conversion_error') == 2, text
    label, conversions = None, 0
    for line in text.splitlines():
        head = line.split(';')[0].rstrip()
        if head and not head[0].isspace() and head.endswith(':'):
            label = head
        elif 'fptosi double' in line:
            # Only reachable after the range test passed.
            assert label and label.startswith('conv.ok'), (label, text)
            conversions += 1
    assert conversions == 2, text
    return 1


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='trunc-round-') as tmp:
        work = Path(tmp)
        todo = list(jobs())
        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(lambda job: check(work, job), todo))
        device = check_device(work)
        check_ir(work)
    print(f'PASS: TRUNC/ROUND INTEGER range: {len(todo)} runtime cells (both '
          'dialects, MATHCK+ and MATHCK-, O0-O3); range test before fptosi '
          f'in IR; {device} DEVICE cells (CPU host failure, NVPTX saturates)')


if __name__ == '__main__':
    main()
