#!/usr/bin/env python3
"""Scalar arithmetic safety oracles; no UB outputs or Python parity."""
import json
import re
import resource
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(cmd):
    return subprocess.run(cmd,
                          cwd=ROOT,
                          text=True,
                          capture_output=True,
                          timeout=30)


def compile_source(work, source, dialect, opt, ir=False):
    path = work / 'source.pas'
    path.write_text(source)
    output = work / ('probe.ll' if ir else 'probe')
    cmd = [
        'bin/pascal1981', '--dialect', dialect, f'-O{opt}',
        str(path), '-o',
        str(output)
    ]
    if ir:
        cmd.insert(1, '-S')
    result = run(cmd)
    assert result.returncode == 0, (source, result.stderr)
    return output


def success_source(widths, flag):
    declarations, statements, expected = [], [], []
    for width in widths:
        signed = 'INTEGER' if width == 16 else f'INTEGER{width}'
        unsigned = 'WORD' if width == 16 else f'WORD{width}'
        declarations += [
            f'a{width}, b{width}: {signed};',
            f'u{width}, v{width}: {unsigned};'
        ]
        # Build MIN at runtime, avoiding the separate >2^53 literal gap.
        statements += [f'a{width} := -1; b{width} := 2;']
        statements += [f'a{width} := a{width} * b{width};'] * (width - 1)
        # MIN DIV -1 returns MIN only unchecked; MATHCK+ overflow is
        # covered by mathck_overflow.py. MIN MOD -1 is 0 either way.
        statements += [f'b{width} := -1;']
        if flag == '-':
            statements += [f'WRITELN(a{width} DIV b{width});']
            expected += [str(-(1 << (width - 1)))]
        statements += [f'WRITELN(a{width} MOD b{width});']
        expected += ['0']
        for a, b in [(-7, 2), (7, -2), (-7, -2), (0, -1), (7, 1)]:
            statements += [
                f'a{width} := {a}; b{width} := {b};',
                f'WRITELN(a{width} DIV b{width});',
                f'WRITELN(a{width} MOD b{width});'
            ]
            quotient = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
            expected += [str(quotient), str(a - quotient * b)]
        maximum = (1 << width) - 1
        max_expr = 'MAXWORD64' if width == 64 else str(maximum)
        statements += [
            f'u{width} := {max_expr}; v{width} := 2;',
            f'WRITELN(u{width} DIV v{width});',
            f'WRITELN(u{width} MOD v{width});'
        ]
        expected += [str(maximum // 2), '1']
    source = f'{{$MATHCK{flag}}}\nPROGRAM Safety;\nVAR ' + '\n'.join(
        declarations)
    source += '\nBEGIN\n' + '\n'.join(statements) + '\nEND.\n'
    return source, '\n'.join(expected) + '\n'


def zero_source(tk, left, op, flag):
    return f'''{{$MATHCK{flag}}}
PROGRAM ZeroProbe;
FUNCTION LeftValue: {tk};
BEGIN WRITELN('left'); LeftValue := {left} END;
FUNCTION RightValue: {tk};
BEGIN WRITELN('right'); RightValue := 0 END;
BEGIN
  WRITELN('prefix');
  WRITELN(LeftValue {op} RightValue);
  WRITELN('unreachable')
END.
'''


def check_ir(text, widths):
    # Every division uses the sanitized select, after the zero branch.
    functions = re.findall(r'define .*?\n}', text, re.S)
    found = 0
    for function in functions:
        for match in re.finditer(
                r'= (?:sdiv|srem|udiv|urem) i(8|16|32|64) [^,]+, (%[-\w.]+)',
                function):
            width, divisor = match.groups()
            before = function[:match.start()]
            assert re.search(
                re.escape(divisor) + r' = select i1 .*?, i' + width +
                r' 1, i' + width, before), match[0]
            assert 'label %div.bad' in before and 'div.ok' in before, match[0]
            found += 1
    assert found >= len(widths) * 4, found
    assert 'poison' not in text and 'undef' not in text


def strip_snapshots(value):
    if isinstance(value, list):
        return [strip_snapshots(item) for item in value]
    if isinstance(value, dict):
        return {
            key: strip_snapshots(item)
            for key, item in value.items()
            if key not in ('mathck', 'op_location')
        }
    return value


def check_legacy_location():
    # Codegen takes coordinates only from the operation's own snapshot; a
    # legacy typed AST without one still gets the mandatory guard at 0:0.
    for dialect in ['vintage', 'extended']:
        text = zero_source('INTEGER', '-7', 'DIV', '+')
        for stage in ['lexer', 'parser', 'typechecker']:
            cmd = [f'bin/{stage}']
            if stage != 'lexer':
                cmd += ['--dialect', dialect]
            result = subprocess.run(cmd,
                                    cwd=ROOT,
                                    input=text,
                                    text=True,
                                    capture_output=True,
                                    timeout=30)
            assert result.returncode == 0, result.stderr
            text = result.stdout
        legacy = json.dumps(strip_snapshots(json.loads(text)))
        assert '"op_location"' in text and '"op_location"' not in legacy
        for typed, coords in [(text, 'i32 9, i32 21)'),
                              (legacy, 'i32 0, i32 0)')]:
            result = subprocess.run(['bin/codegen', '--dialect', dialect],
                                    cwd=ROOT,
                                    input=typed,
                                    text=True,
                                    capture_output=True,
                                    timeout=30)
            assert result.returncode == 0, result.stderr
            calls = [
                line for line in result.stdout.splitlines()
                if 'call void @pas_math_zero' in line
            ]
            assert len(calls) == 1 and calls[0].endswith(coords), calls


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    cells = 0
    with tempfile.TemporaryDirectory(prefix='divmod-safety-') as tmp:
        work = Path(tmp)
        for dialect, widths in [('vintage', [16]),
                                ('extended', [8, 16, 32, 64])]:
            for flag in ['+', '-']:
                source, expected = success_source(widths, flag)
                for opt in range(4):
                    exe = compile_source(work, source, dialect, opt)
                    result = run([str(exe)])
                    assert (result.returncode, result.stdout,
                            result.stderr) == (0, expected, ''), result
                    cells += 1
                ir = compile_source(work, source, dialect, 0,
                                    ir=True).read_text()
                check_ir(ir, widths)
                for width in widths:
                    for unsigned in [False, True]:
                        tk = ('WORD' if unsigned else
                              'INTEGER') + (str(width) if width != 16 else '')
                        left = ('MAXWORD64' if width == 64 else
                                str((1 << width) - 1)) if unsigned else '-7'
                        value = str((1 << width) - 1) if unsigned else '-7'
                        for op in ['DIV', 'MOD']:
                            source = zero_source(tk, left, op, flag)
                            expected_error = (
                                f'runtime error: MATHCK {"unsigned" if unsigned else "signed"} '
                                f'division by zero in {op} at line 9 column 21 '
                                f'(left={value}, right=0)\n')
                            for opt in range(4):
                                exe = compile_source(work, source, dialect,
                                                     opt)
                                result = run([str(exe)])
                                assert result.returncode != 0, result
                                assert result.stdout == 'prefix\nleft\nright\n', result
                                assert result.stderr == expected_error, result
                                cells += 1
        # Constant zero divisors are compile-time errors; covered by
        # mathck_constant_folding.py. Dynamic zeros above still trap.
        # NVPTX has no host failure path: reject instead of omitting safety.
        template = (ROOT /
                    'tests/fixtures/mathck/divmod_device.pas').read_text()
        for flag in ['+', '-']:
            for op in ['DIV', 'MOD']:
                text = f'{{$MATHCK{flag}}}\n' + template.replace(
                    'a DIV b', f'a {op} b')
                for stage in ['lexer', 'parser', 'typechecker']:
                    cmd = [f'bin/{stage}']
                    if stage != 'lexer':
                        cmd += ['--dialect', 'extended']
                    result = subprocess.run(cmd,
                                            cwd=ROOT,
                                            input=text,
                                            text=True,
                                            capture_output=True,
                                            timeout=30)
                    assert result.returncode == 0, result.stderr
                    text = result.stdout
                result = subprocess.run([
                    'bin/codegen', '--dialect', 'extended', '--emit-ptx',
                    '--device-triple', 'nvptx64-nvidia-cuda'
                ],
                                        cwd=ROOT,
                                        input=text,
                                        text=True,
                                        capture_output=True,
                                        timeout=30)
                assert result.returncode != 0, result
                # MATHCK+ reaches the located DEVICE boundary first; under
                # MATHCK- the mandatory zero-divisor safety still rejects.
                if flag == '+':
                    assert ('MATHCK unsupported boundary: DEVICE arithmetic '
                            'at line ') in result.stderr, result
                else:
                    assert 'scalar DIV/MOD safety is unsupported on DEVICE' in result.stderr, result
                assert not result.stdout, result
                result = subprocess.run(
                    ['bin/codegen', '--dialect', 'extended'],
                    cwd=ROOT,
                    input=text,
                    text=True,
                    capture_output=True,
                    timeout=30)
                assert result.returncode == 0, result.stderr
                assert 'call void @pas_math_zero' in result.stdout
                assert 'div.safe' in result.stdout and 'label %div.bad' in result.stdout
        check_legacy_location()
    print(
        f'PASS: scalar DIV/MOD safety: {cells} runtime cells, all widths, both settings, O0-O3; guarded IR; NVPTX rejection/CPU-device guards; snapshot/legacy diagnostic coordinates'
    )


if __name__ == '__main__':
    main()
