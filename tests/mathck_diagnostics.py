#!/usr/bin/env python3
"""MATHCK diagnostics are located and distinct from the other checks'.

Every MATHCK runtime class (signed/unsigned overflow in an operator, unary
minus, a scoped builtin and a VECTOR reduction; signed/unsigned division by
zero) prints exactly one `runtime error: MATHCK ...` line carrying the
operator or function-name token's line and column, after flushing stdout.
The neighbouring failures -- RANGECK subrange stores and SUCC/PRED domains,
INDEXCK bounds, INITCK reads, TRUNC/ROUND conversion -- keep their own
texts, never the MATHCK stem. RANGECK and INDEXCK messages are still
unlocated (their own records decide that). Exact text at O0 and O2.
"""
import re
import resource
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import run

PROLOGUE = [
    'PROGRAM Diag(output);', 'TYPE Colour = (red, green, blue);',
    '  V = VECTOR [4] OF INTEGER;',
    'VAR i, k: INTEGER; w, z: WORD; s: 0..3; c: Colour; r: REAL;',
    '  a: ARRAY [1..3] OF INTEGER; u: V; t: INTEGER;', 'BEGIN',
    '  i := 32767; k := 0; w := 65535; z := 0; c := blue; r := 1.0E9;',
    '  u := VSPLAT(20000, V); t := 0;'
]
STEM = re.compile(
    r'runtime error: MATHCK (signed|unsigned) (overflow|division '
    r'by zero) in (\S+) at line (\d+) column (\d+) \(.+\)\n')

# (tag, statement, column token, expected stderr with {line}/{col}).
MATHCK_CASES = [
    ('add', 'k := i + 1', '+', 'MATHCK signed overflow in + at line {line} '
     'column {col} (left=32767, right=1)'),
    ('wmul', 'w := w * 2', '*', 'MATHCK unsigned overflow in * at line {line} '
     'column {col} (left=65535, right=2)'),
    ('neg', 'i := -32768; k := -i', '-i', 'MATHCK signed overflow in - at '
     'line {line} column {col} (operand=-32768)'),
    ('succ', 'k := SUCC(i)', 'SUCC', 'MATHCK signed overflow in SUCC at line '
     '{line} column {col} (operand=32767)'),
    ('vsum', 't := VSUM(u)', 'VSUM', 'MATHCK signed overflow in VSUM at line '
     '{line} column {col} (left=20000, right=20000)'),
    ('div0', 'k := i DIV k', 'DIV', 'MATHCK signed division by zero in DIV '
     'at line {line} column {col} (left=32767, right=0)'),
    ('wmod0', 'w := w MOD z', 'MOD', 'MATHCK unsigned division by zero in MOD '
     'at line {line} column {col} (left=65535, right=0)'),
]
# Zero divisors fail under MATHCK- too; overflow wraps there.
MATHCK_OFF_FAILS = {'div0', 'wmod0'}
OTHER_CASES = [
    ('range', 'k := 5; s := k', None, 'value 5 is outside subrange 0..3'),
    ('domain', 'c := SUCC(c)', None, 'value 3 is outside subrange 0..2'),
    ('index', 'k := 4; a[k] := 1', None, 'array index 4 is outside bounds '
     '1..3'),
    ('trunc', 'k := TRUNC(r)', 'TRUNC', 'TRUNC result out of INTEGER range at '
     'line {line} column {col} (value=1000000000)'),
]


def program(statement, flag):
    lines = [f'{{$MATHCK{flag}}}'] + PROLOGUE + ["  WRITELN('prefix');"]
    line = len(lines) + 1
    lines += [f'  {statement};', "  WRITELN('after')", 'END.']
    return '\n'.join(lines) + '\n', line


def expected(statement, token, text, line):
    col = 0
    if token:
        source = f'  {statement};'
        col = source.index(token, source.rindex(':=')) + 1
    return 'runtime error: ' + text.format(line=line, col=col) + '\n'


def initck_program():
    lines = [
        'PROGRAM Init(output);', 'PROCEDURE p;', 'VAR x: INTEGER;', 'BEGIN',
        "  WRITELN('prefix');", '  {$INITCK+} WRITELN(x)', 'END;', 'BEGIN',
        '  p', 'END.'
    ]
    col = lines[5].index('x)') + 1
    return '\n'.join(lines) + '\n', ('runtime error: INITCK uninitialized '
                                     f'local x at line 6 column {col}\n')


def jobs():
    for opt in (0, 2):
        for flag in ('+', '-'):
            for tag, statement, token, text in MATHCK_CASES:
                source, line = program(statement, flag)
                if flag == '+' or tag in MATHCK_OFF_FAILS:
                    want = expected(statement, token, text, line)
                else:
                    want = None
                yield (f'{tag}_{flag == "+"}_O{opt}', source, opt, want, True)
        for tag, statement, token, text in OTHER_CASES:
            source, line = program(statement, '+')
            yield (f'{tag}_O{opt}', source, opt,
                   expected(statement, token, text, line), False)
        source, want = initck_program()
        yield (f'initck_O{opt}', source, opt, want, False)


def check(work, job):
    tag, source, opt, want, is_mathck = job
    path = work / f'{tag}.pas'
    exe = work / tag
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', 'extended', f'-O{opt}',
        str(path), '-o',
        str(exe)
    ])
    assert built.returncode == 0, (tag, built.stderr)
    result = run([str(exe)])
    if want is None:
        # MATHCK- overflow wraps and the program finishes.
        assert result.returncode == 0, (tag, result)
        assert result.stderr == '' and result.stdout.endswith('after\n'), \
            (tag, result)
        return
    assert result.returncode != 0, (tag, result)
    assert (result.stdout, result.stderr) == ('prefix\n', want), (tag, result)
    # One line; MATHCK classes match the shared stem, others never use it.
    assert result.stderr.count('\n') == 1, (tag, result.stderr)
    assert bool(STEM.fullmatch(result.stderr)) == is_mathck, (tag,
                                                              result.stderr)
    assert ('MATHCK' in result.stderr) == is_mathck, (tag, result.stderr)


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    todo = list(jobs())
    with tempfile.TemporaryDirectory(prefix='mathck-diag-') as tmp:
        work = Path(tmp)
        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(lambda job: check(work, job), todo))
    print(f'PASS: MATHCK diagnostics: {len(todo)} cells (each MATHCK class '
          'located at its token under MATHCK+, zero divisors under MATHCK- '
          'too, overflow wraps under MATHCK-; RANGECK/INDEXCK/INITCK/TRUNC '
          'failures keep distinct texts; O0/O2)')


if __name__ == '__main__':
    main()
