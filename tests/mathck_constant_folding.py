#!/usr/bin/env python3
"""Truncating constant DIV/MOD, consumer adaptation, and zero rejection."""
import json
import tempfile
from pathlib import Path

from mathck_divmod_safety import compile_source, run


def stage(name, text, dialect='extended'):
    import subprocess
    cmd = [f'bin/{name}']
    if name != 'lexer':
        cmd += ['--dialect', dialect]
    return subprocess.run(cmd,
                          input=text,
                          text=True,
                          capture_output=True,
                          timeout=30)


def main():
    cells = rejects = 0
    with tempfile.TemporaryDirectory(prefix='constant-folding-') as tmp:
        work = Path(tmp)
        for dialect in ['vintage', 'extended']:
            for flag in ['+', '-']:
                statements, expected = [], []
                for a, b in [(-7, 2), (7, -2), (-7, -2), (7, 2), (-8, 2),
                             (0, -2), (-32768, -1)]:
                    # Target coercion invokes the folder, while the variable
                    # twins exercise ordinary runtime lowering.
                    for op in ['DIV', 'MOD']:
                        q = abs(a) // abs(b) * (-1 if
                                                (a < 0) != (b < 0) else 1)
                        value = q if op == 'DIV' else a - q * b
                        if a == -32768 and b == -1 and op == 'DIV':
                            continue  # exact constant result is out of range
                        statements += [
                            f'k := ({a}) {op} ({b}); WRITELN(k);',
                            f'a := {a}; b := {b}; WRITELN(a {op} b);'
                        ]
                        expected += [str(value)] * 2
                source = f'''{{$MATHCK{flag}}}
PROGRAM FoldProbe;
VAR a, b, k: INTEGER;
BEGIN
{chr(10).join(statements)}
END.
'''
                for opt in range(4):
                    exe = compile_source(work, source, dialect, opt)
                    result = run([str(exe)])
                    assert (result.returncode, result.stdout,
                            result.stderr) == (0, '\n'.join(expected) + '\n',
                                               ''), result
                    cells += 1
                # Zero is forbidden with either a constant or dynamic dividend,
                # also through CONST names and nested arithmetic.
                for op in ['DIV', 'MOD']:
                    for dividend in ['7', 'a']:
                        for divisor in ['0', 'Z', '(2 - 2)', '(Z DIV 2)']:
                            text = f'''{{$MATHCK{flag}}}
PROGRAM Bad; CONST Z = 0; VAR a: INTEGER;
BEGIN a := 7; WRITELN({dividend} {op} {divisor}) END.
'''
                            path = work / 'bad.pas'
                            path.write_text(text)
                            for opt in [0, 2]:
                                out = work / 'bad.ll'
                                out.unlink(missing_ok=True)
                                result = run([
                                    'bin/pascal1981', '-S', '--dialect',
                                    dialect, f'-O{opt}',
                                    str(path), '-o',
                                    str(out)
                                ])
                                assert result.returncode != 0, text
                                assert 'Constant division by zero' in result.stderr, result
                                assert not out.exists(), result
                                rejects += 1
        # Large INTEGER constant index/coercion must be rebuilt from the exact
        # truncating fold, not the already truncated i16 operand. G22 too.
        source = '''PROGRAM Consumers;
CONST N = -65537;
TYPE Edge = ARRAY [-32768..-32767] OF INTEGER;
VAR a: Edge; k: INTEGER; wide: INTEGER32;
BEGIN
  k := N DIV 2; WRITELN(k);
  a[N DIV 2] := 42; WRITELN(a[-32768]);
  wide := (-7) DIV 2; WRITELN(wide);
  wide := 100000 + ((-7) MOD 2); WRITELN(wide)
END.
'''
        for flag in ['+', '-']:
            for opt in range(4):
                exe = compile_source(work, f'{{$MATHCK{flag}}}\n' + source,
                                     'extended', opt)
                result = run([str(exe)])
                assert (result.returncode, result.stdout,
                        result.stderr) == (0, '-32768\n42\n-3\n99999\n',
                                           ''), result
                cells += 1
        # CONST/CASE/bound grammars admit constants, not binary expressions.
        # Feed an otherwise parser-produced AST with a BinOp CONST value to
        # exercise both folders directly, including frozen/legacy AST input.
        text = 'PROGRAM ASTProbe; CONST N = -3; TYPE A = ARRAY [N..0] OF INTEGER; VAR x: A; k: INTEGER; BEGIN x[N] := 9; k := N; CASE k OF N: WRITELN(x[N]) END END.'
        lexed = stage('lexer', text)
        parsed = stage('parser', lexed.stdout)
        assert parsed.returncode == 0, parsed.stderr
        ast = json.loads(parsed.stdout)

        # Discover node discriminator from the parser rather than inventing it.
        def find_const(node):
            if isinstance(node, dict):
                if 'ConstDecl' in node.values():
                    return node
                for value in node.values():
                    found = find_const(value)
                    if found:
                        return found
            elif isinstance(node, list):
                for value in node:
                    found = find_const(value)
                    if found:
                        return found

        decl = find_const(ast)
        assert decl is not None
        literal = decl['value']
        discriminator = next(key for key, value in literal.items()
                             if value == 'IntLiteral')
        for op, right in [('DIV', 2), ('MOD', 2), ('DIV', 0), ('MOD', 0)]:
            decl['value'] = {
                discriminator: 'BinOp',
                'op': op,
                'left': {
                    discriminator: 'IntLiteral',
                    'value': -7
                },
                'right': {
                    discriminator: 'IntLiteral',
                    'value': right
                }
            }
            raw = json.dumps(ast)
            checked = stage('typechecker', raw)
            # Test codegen's folder independently, bypassing typechecking too.
            lowered = stage('codegen', raw)
            if right == 0:
                for result in [checked, lowered]:
                    assert result.returncode != 0, result
                    assert 'Constant division by zero' in result.stderr, result
                    assert not result.stdout, result
            else:
                assert checked.returncode == 0, checked.stderr
                assert lowered.returncode == 0, lowered.stderr
                folded = -3 if op == 'DIV' else -1
                assert f'i16 {folded}' in lowered.stdout, lowered.stdout
                assert 'poison' not in lowered.stdout
    print(
        f'PASS: constant DIV/MOD folding: {cells} runtime cells, {rejects} zero rejections; CONST/CASE/bounds AST consumers'
    )


if __name__ == '__main__':
    main()
