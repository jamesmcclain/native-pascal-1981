#!/usr/bin/env python3
"""Pin the arithmetic dependencies found by the self-hosting source audit."""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

from mathck_divmod_safety import compile_source, run

ROOT = Path(__file__).resolve().parents[1]


def stage(binary, text, dialect='extended', cwd=None):
    command = [str(ROOT / binary)]
    if Path(binary).name != 'lexer':
        command += ['--dialect', dialect]
    result = subprocess.run(command,
                            input=text,
                            text=True,
                            capture_output=True,
                            cwd=cwd,
                            timeout=60)
    assert result.returncode == 0, result.stderr
    return result.stdout


def function(ir, name):
    match = re.search(r'^define [^\n]*@' + name + r'\([^\n]*\).*?^}', ir,
                      re.M | re.S | re.I)
    assert match, name
    return match.group()


def main():
    # The only MATHCK- region in compiler Pascal source is the label key
    # converter. Check actual lexer flags, including restoration afterwards.
    source = (ROOT / 'src/ps_base.pas').read_text()
    tokens = json.loads(stage('bin/lexer', source, cwd=ROOT / 'src'))
    unchecked = [t for t in tokens if not t['flags']['MATHCK']]
    kinds = [t['kind'] for t in unchecked]
    assert kinds.count('MUL') == 1 and kinds.count('PLUS') == 1, kinds
    assert kinds.count('MINUS') == 2, kinds  # digit subtraction and negation
    first = next(i for i, t in enumerate(tokens) if not t['flags']['MATHCK'])
    last = max(i for i, t in enumerate(tokens) if not t['flags']['MATHCK'])
    assert all(t['flags']['MATHCK']
               for t in tokens[:first] + tokens[last + 1:])
    assert any(t['lexeme'].upper() == 'STRTOREALVAL'
               for t in tokens[last + 1:])

    # Emit actual compiler units, not copied limit formulas: both WORD limit
    # constructors and INTEGER32 build-ups must perform wide arithmetic.
    for unit, names in [('tc_expr', ['MaxWord16Value', 'MaxInteger32Value']),
                        ('cg_decl', ['ConstIntegerType',
                                     'MaxConstInteger32'])]:
        text = (ROOT / f'src/{unit}.pas').read_text()
        for tool in ['lexer', 'parser', 'typechecker', 'codegen']:
            text = stage(f'bin/{tool}', text, cwd=ROOT / 'src')
        for name in names:
            body = function(text, name)
            # MATHCK+ compiler sources lower to checked i64 intrinsics.
            assert re.search(r'\b(?:mul i64|smul\.with\.overflow\.i64)\b',
                             body), (name, body)
            assert re.search(r'\b(?:add i64|sadd\.with\.overflow\.i64)\b',
                             body), (name, body)
            assert not re.search(
                r'\b(?:(?:mul|add) i16|with\.overflow\.i16)\b', body), (name,
                                                                        body)

    labels = '''PROGRAM LabelKeys(OUTPUT);
LABEL 32767, 32768, 40000, 65535;
BEGIN
  GOTO 32767;
32767: WRITELN('32767'); GOTO 32768;
32768: WRITELN('32768'); GOTO 40000;
40000: WRITELN('40000'); GOTO 65535;
65535: WRITELN('65535')
END.
'''
    # Gen1's lexer/parser are native programs too; check the actual numeric
    # label keys at every bootstrap generation, with both dialects.
    for generation in range(1, 5):
        for dialect in ['vintage', 'extended']:
            text = stage(f'build/gen{generation}/lexer', labels, dialect)
            ast = json.loads(
                stage(f'build/gen{generation}/parser', text, dialect))

            # AST Program declaration holds labels under the block.
            def label_lists(node):
                if isinstance(node, dict):
                    for key, value in node.items():
                        if key == 'labels':
                            yield value
                        else:
                            yield from label_lists(value)
                elif isinstance(node, list):
                    for value in node:
                        yield from label_lists(value)

            assert [32767, -32768, -25536, -1] in list(label_lists(ast)), ast

    cells = 0
    with tempfile.TemporaryDirectory(prefix='mathck-bootstrap-') as tmp:
        work = Path(tmp)
        # Check ignored directives at every Clang optimization level as well
        # as the ordinary pasboot fixture harness's O1 run.
        pasboot = str(ROOT / 'bootstrap/build/pasboot')
        for name in ['testio', 'mathck_ignored']:
            result = run([
                pasboot, f'bootstrap/tests/{name}.pas', '-o',
                str(work / f'{name}.c')
            ])
            assert result.returncode == 0, result.stderr
        for opt in range(4):
            exe = work / 'pasboot-probe'
            result = run([
                os.environ.get('CLANG', 'clang'), f'-O{opt}', '-fwrapv', '-w',
                '-Ibootstrap',
                str(work / 'testio.c'),
                str(work / 'mathck_ignored.c'), 'runtime/build/libpascalrt.a',
                '-o',
                str(exe)
            ])
            assert result.returncode == 0, result.stderr
            result = run([str(exe)])
            assert (result.returncode, result.stdout, result.stderr) == (0, (
                ROOT / 'bootstrap/tests/mathck_ignored.out').read_text(), '')
        for directive in ['MATHCK', 'MATHCK:', 'MATHCK:+', 'MATHCK+garbage']:
            path = work / 'bad.pas'
            path.write_text('{$' + directive + '}\nPROGRAM Bad; BEGIN END.')
            result = run([pasboot, '--parse-only', str(path)])
            assert result.returncode != 0 and 'malformed $MATHCK' in result.stderr
        for dialect in ['vintage', 'extended']:
            for flag in ['+', '-']:
                for opt in range(4):
                    exe = compile_source(work, f'{{$MATHCK{flag}}}\n' + labels,
                                         dialect, opt)
                    result = run([str(exe)])
                    assert (result.returncode, result.stdout,
                            result.stderr) == (0,
                                               '32767\n32768\n40000\n65535\n',
                                               ''), result
                    cells += 1
    print(
        f'mathck bootstrap audit: flags, wide limit IR, 8 generation/dialect '
        f'label-key checks, {cells} native runtime cells, 4 pasboot runtime '
        f'cells and malformed-directive checks passed')


if __name__ == '__main__':
    main()
