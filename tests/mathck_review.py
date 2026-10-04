#!/usr/bin/env python3
"""Regressions from the /code-review of the MATHCK range (e615783..c0cb96f).

1. Operations whose operands are enum-member constants (`ORD(b) * 20000`)
   are constants to the codegen folder but not to the typechecker, which
   neither folds nor range-checks them. Codegen must exempt only operations
   the typechecker folded and tagged. These must be checked at run time
   under MATHCK+ (located trap) and wrap under MATHCK- for + - *, negation
   and signed DIV by -1, at O0 and O2; on NVPTX they are DEVICE boundaries.
   Found while fixing it: ORD of any enum value was tagged INTEGER32 in
   codegen (INTEGER in the typechecker), so `ORD(e) * 20000` was checked at
   32 bits and truncated into INTEGER; ORD of an enum is now INTEGER.
2. One constant zero divisor gives exactly one `Constant division by zero`.
3. A subrange variable as the VAR C of SADDOK/SMULOK/UADDOK/UMULOK is a
   typechecker error (VAR needs the identical type), not a codegen abort.
"""
import resource
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_device import compile_nvptx
from mathck_overflow import run

PROLOGUE = [
    'PROGRAM Enum(output);', 'TYPE C = (r, g, b);', 'VAR i: INTEGER; e: C;',
    'BEGIN'
]
# (statement, token, MATHCK+ diagnostic tail, MATHCK- output).
ENUM_CASES = [
    ('i := ORD(b) * 20000', '*', 'signed overflow in * at line {line} column '
     '{col} (left=2, right=20000)', '-25536'),
    ('i := 32767 + ORD(g)', '+', 'signed overflow in + at line {line} column '
     '{col} (left=32767, right=1)', '-32768'),
    ('i := ORD(r) - 32767 - ORD(b)', '- ORD(b)',
     'signed overflow in - at line '
     '{line} column {col} (left=-32767, right=2)', '32767'),
    ('i := -(ORD(r) - 32767 - ORD(g))', '-(', 'signed overflow in - at line '
     '{line} column {col} (operand=-32768)', '-32768'),
    ('i := (ORD(r) - 32767 - ORD(g)) DIV (ORD(r) - ORD(g))', 'DIV',
     'signed overflow in DIV at line {line} column {col} (left=-32768, '
     'right=-1)', '-32768'),
    # ORD of an enum variable is INTEGER, not a 32-bit value that is
    # checked at 32 bits and then silently truncated.
    ('e := b; i := ORD(e) * 20000', '*', 'signed overflow in * at line '
     '{line} column {col} (left=2, right=20000)', '-25536'),
]


def build_run(work, tag, source, opt, dialect='vintage'):
    path = work / f'{tag}.pas'
    exe = work / tag
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', dialect, f'-O{opt}',
        str(path), '-o',
        str(exe)
    ])
    if built.returncode:
        return built, None
    return built, run([str(exe)])


def check_enum_constants(work):
    cells = 0
    for index, (statement, token, tail, wrapped) in enumerate(ENUM_CASES):
        for flag in '+-':
            lines = [f'{{$MATHCK{flag}}}'] + PROLOGUE
            line = len(lines) + 1
            lines += [f'  {statement};', '  WRITELN(i)', 'END.']
            source = '\n'.join(lines) + '\n'
            text = f'  {statement};'
            col = text.index(token, text.index(':=')) + 1
            for opt in (0, 2):
                built, result = build_run(work,
                                          f'enum{index}{flag == "+"}{opt}',
                                          source, opt)
                assert built.returncode == 0, (statement, built.stderr)
                if flag == '+':
                    want = ('runtime error: MATHCK ' +
                            tail.format(line=line, col=col) + '\n')
                    assert result.returncode != 0, (statement, opt, result)
                    assert (result.stdout, result.stderr) == ('', want), \
                        (statement, opt, result)
                else:
                    assert (result.returncode, result.stdout,
                            result.stderr) == (0, wrapped + '\n', ''), \
                        (statement, opt, result)
                cells += 1
    # Non-overflowing enum-constant operations keep their exact values.
    source = '\n'.join(['{$MATHCK+}'] + PROLOGUE + [
        '  i := ORD(b) * 100 - ORD(g); WRITELN(i);',
        '  i := -(ORD(b) * 16383 + 1); WRITELN(i);',
        '  i := (ORD(b) - 32767) DIV (ORD(r) - ORD(g)); WRITELN(i)', 'END.'
    ]) + '\n'
    for opt in (0, 2):
        built, result = build_run(work, f'enum_ok{opt}', source, opt)
        assert built.returncode == 0, built.stderr
        assert (result.returncode, result.stdout,
                result.stderr) == (0, '199\n-32767\n32765\n', ''), result
        cells += 1
    # NVPTX: a checked enum-constant operation is a DEVICE boundary.
    for flag in '+-':
        source = ('DEVICE MODULE DevEnum;\nTYPE C = (r, g, b);\n'
                  f'VAR i: INTEGER;\n{{$MATHCK{flag}}}\nPROCEDURE work;\n'
                  'BEGIN\n  i := ORD(b) * 2\nEND;\n.\n')
        result, _ = compile_nvptx(work, f'dev{flag == "+"}', source)
        if flag == '+':
            col = '  i := ORD(b) * 2'.index('*') + 1
            assert result.returncode != 0 and result.stderr == (
                'MATHCK unsupported boundary: DEVICE arithmetic at line 7 '
                f'column {col}\n'), result
        else:
            assert result.returncode == 0, result.stderr
        cells += 1
    return cells


def check_zero_divisor_once(work):
    cells = 0
    for statement in [
            'i := 5 DIV 0', 'WRITELN(7 MOD (2-2))', 'i := i DIV (3-3)',
            'i := (4 DIV 0) + 1'
    ]:
        for dialect in ('vintage', 'extended'):
            source = ('PROGRAM Z(output);\nVAR i: INTEGER;\nBEGIN\n  i := 1;\n'
                      f'  {statement}\nEND.\n')
            built, _ = build_run(work, f'zero{cells}', source, 0, dialect)
            assert built.returncode != 0, statement
            assert built.stderr.count('Constant division by zero') == 1, \
                (statement, dialect, built.stderr)
            cells += 1
    return cells


def check_saddok_subrange(work):
    cells = 0
    for name, host in [('SADDOK', 'INTEGER'), ('SMULOK', 'INTEGER'),
                       ('UADDOK', 'WORD'), ('UMULOK', 'WORD')]:
        for target, decl in [('c', 'c: 0..100;'),
                             ('rec.f', 'rec: RECORD '
                              'f: 0..100 END;'), ('ok', f'ok: {host};')]:
            source = (f'PROGRAM S(output);\nVAR a, x: {host}; {decl}\n'
                      f'BEGIN\n  a := 1; x := 2;\n'
                      f'  IF {name}(a, x, {target}) THEN WRITELN({target})\n'
                      'END.\n')
            built, result = build_run(work, f'sad{cells}', source, 0)
            if target == 'ok':
                assert built.returncode == 0, built.stderr
                assert result.stdout == ('3\n' if 'ADD' in name else '2\n'), \
                    result
            else:
                assert built.returncode != 0, (name, target)
                assert 'codegen:' not in built.stderr, built.stderr
                assert (f'VAR argument type mismatch in call to {name}'
                        in built.stderr), built.stderr
            cells += 1
    return cells


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-review-') as tmp:
        work = Path(tmp)
        enum = check_enum_constants(work)
        zero = check_zero_divisor_once(work)
        saddok = check_saddok_subrange(work)
    print(f'PASS: MATHCK review regressions: {enum} enum-constant cells '
          '(checked under MATHCK+, wrap under MATHCK-, exact otherwise, NVPTX '
          f'boundary); {zero} single zero-divisor diagnostic cells; {saddok} '
          'SADDOK-family VAR C cells (subranges rejected by the typechecker)')


if __name__ == '__main__':
    main()
