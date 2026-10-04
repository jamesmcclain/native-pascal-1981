#!/usr/bin/env python3
"""MATHCK and RANGECK on the scoped builtins SUCC/PRED/ABS/SQR, and the
never-trapping IBM library functions SADDOK/SMULOK/UADDOK/UMULOK.

Integer-family SUCC/PRED/ABS/SQR are MATHCK operations at the argument's own
width; CHAR, BOOLEAN, enumeration and subrange SUCC/PRED domains are RANGECK. Oracles come from exact
integer arithmetic, never from a previous compiler's output. Every runtime
cell runs at O0-O3.
"""
import json
import math
import resource
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from mathck_overflow import (OPTS, compile_and_run, limits, matrix, run, setup,
                             strip_snapshots, type_name, typed_ast, wrap)

STEP = {'SUCC': 1, 'PRED': -1}


def exact_call(name, value):
    if name == 'ABS':
        return abs(value)
    if name == 'SQR':
        return value * value
    return value + STEP[name]


def step_program(width, unsigned, flag, rows):
    tk = type_name(width, unsigned)
    names = {f'v{index}': value for index, (_, value) in enumerate(rows)}
    source = [
        f'{{$MATHCK{flag}}}', 'PROGRAM Steps;',
        f'VAR {", ".join(names)}: {tk};', 'BEGIN'
    ]
    source += setup(names)
    source += [
        f'WRITELN({name}(v{index}));' for index, (name, _) in enumerate(rows)
    ]
    return '\n'.join(source + ['END.']) + '\n'


def step_failure(width, unsigned, name, value):
    tk = type_name(width, unsigned)
    source = [
        '{$MATHCK+}', 'PROGRAM StepFailure;', f'VAR g: {tk};',
        f"FUNCTION A: {tk}; BEGIN WRITELN('arg'); A := g END;", 'BEGIN'
    ]
    source += setup({'g': value}) + ["WRITELN('prefix');"]
    call = f'  WRITELN({name}(A));'
    line = len(source) + 1
    source += [call, "  WRITELN('unreachable')", 'END.']
    sign = 'unsigned' if unsigned else 'signed'
    stderr = (
        f'runtime error: MATHCK {sign} overflow in {name} at line {line} '
        f'column {call.index(name) + 1} (operand={value})\n')
    return '\n'.join(source) + '\n', 'prefix\narg\n', stderr


def call_rows(width, unsigned):
    """(successes, overflows) for one integer type."""
    low, high = limits(width, unsigned)
    root = math.isqrt(high)  # the largest square that fits is root^2
    ok = [('SUCC', high - 1), ('PRED', low + 1), ('SUCC', low), ('PRED', high),
          ('SUCC', 0), ('PRED', 1), ('ABS', high), ('ABS', 0), ('SQR', root),
          ('SQR', 0), ('SQR', 1)]
    if unsigned:
        # A WORD-family ABS is its argument, high bit included.
        ok += [('ABS', (high >> 1) + 1), ('ABS', 1)]
        bad = [('SUCC', high), ('PRED', low), ('SQR', root + 1), ('SQR', high)]
    else:
        ok += [('SUCC', -1), ('PRED', 0), ('PRED', -1), ('ABS', low + 1),
               ('ABS', -1), ('SQR', -root), ('SQR', -1)]
        bad = [('SUCC', high), ('PRED', low), ('ABS', low), ('SQR', root + 1),
               ('SQR', -root - 1), ('SQR', low)]
    return ok, bad


def step_jobs():
    for dialect, width, unsigned in matrix():
        key = f'{dialect}_{width}_{int(unsigned)}'
        rows, bad = call_rows(width, unsigned)
        expected = ''.join(f'{exact_call(name, value)}\n'
                           for name, value in rows)
        for flag in '+-':
            source = step_program(width, unsigned, flag, rows)
            for opt in OPTS:
                yield f'ok_{key}_{flag == "+"}', source, dialect, opt, (
                    0, expected, '')
        rows = bad
        expected = ''.join(
            f'{wrap(exact_call(name, value), width, unsigned)}\n'
            for name, value in rows)
        source = step_program(width, unsigned, '-', rows)
        for opt in OPTS:
            yield f'wrap_{key}', source, dialect, opt, (0, expected, '')
        for index, (name, value) in enumerate(rows):
            source, stdout, stderr = step_failure(width, unsigned, name, value)
            for opt in OPTS:
                yield f'fail_{key}_{index}', source, dialect, opt, (None,
                                                                    stdout,
                                                                    stderr)
    # REAL ABS/SQR are outside MATHCK and unchanged.
    source = '\n'.join([
        '{$MATHCK+}', 'PROGRAM Reals;', 'VAR r: REAL;', 'BEGIN',
        '  r := -2.5; WRITELN(ABS(r):5:2, SQR(r):6:2)', 'END.'
    ]) + '\n'
    for opt in OPTS:
        yield 'real', source, 'vintage', opt, (0, ' 2.50  6.25\n', '')


DOMAIN_TYPES = """TYPE Color = (red, green, blue); Hue = green..blue; Small = 1..10;
  Top = 0..32767;"""
DOMAIN_VARS = 'VAR c: Color; h: Hue; ch: CHAR; b: BOOLEAN; s: Small; t: Top; i: INTEGER;'


def domain_program(flags, statements):
    return '\n'.join(
        [flags, 'PROGRAM Domain;', DOMAIN_TYPES, DOMAIN_VARS, 'BEGIN'] +
        [f'  {line}' for line in statements] + ['END.']) + '\n'


def domain_jobs():
    """RANGECK owns the CHAR/BOOLEAN/enumeration domains under either MATHCK
    setting; subrange bounds are checked at the store; a base-type extreme
    is MATHCK's and is checked first."""
    successes = [
        "c := red; c := SUCC(c); WRITELN(ORD(c), ' ', ORD(PRED(c)));",
        "c := green; WRITELN(ORD(SUCC(c)), ' ', ORD(PRED(c)));",
        "h := blue; WRITELN(ORD(PRED(h)));",
        "ch := CHR(254); WRITELN(ORD(SUCC(ch)), ' ', SUCC('a'), PRED('b'));",
        "ch := CHR(1); WRITELN(ORD(PRED(ch)));",
        "b := FALSE; WRITELN(SUCC(b), ' ', PRED(SUCC(b)));",
        "s := 9; s := SUCC(s); WRITELN(s, ' ', PRED(s));",
        "t := 32766; t := SUCC(t); WRITELN(t);",
    ]
    expected = '1 0\n2 0\n1\n255 ba\n0\nTRUE FALSE\n10 9\n32767\n'
    for mathck in '+-':
        source = domain_program(f'{{$MATHCK{mathck}}}{{$RANGECK+}}', successes)
        for dialect in ['vintage', 'extended']:
            for opt in OPTS:
                yield (f'domain_ok_{mathck == "+"}', source, dialect, opt,
                       (0, expected, ''))
    failures = [
        ("c := blue; c := SUCC(c);", 'value 3 is outside subrange 0..2'),
        ("c := red; WRITELN(ORD(PRED(c)));",
         'value -1 is outside subrange 0..2'),
        ("ch := CHR(255); ch := SUCC(ch);",
         'value 256 is outside subrange 0..255'),
        ("ch := CHR(0); ch := PRED(ch);",
         'value -1 is outside subrange 0..255'),
        ("b := TRUE; b := SUCC(b);", 'value 2 is outside subrange 0..1'),
        ("b := FALSE; WRITELN(PRED(b));", 'value -1 is outside subrange 0..1'),
        ("s := 10; s := SUCC(s);", 'value 11 is outside subrange 1..10'),
        ("s := 1; s := PRED(s);", 'value 0 is outside subrange 1..10'),
        # The result has the argument's subrange type before any store.
        ("s := 10; i := SUCC(s);", 'value 11 is outside subrange 1..10'),
        ("s := 10; WRITELN(PRED(SUCC(s)));",
         'value 11 is outside subrange 1..10'),
        ("h := green; c := PRED(h);", 'value 0 is outside subrange 1..2'),
    ]
    for index, (statement, message) in enumerate(failures):
        for mathck in '+-':
            source = domain_program(
                f'{{$MATHCK{mathck}}}{{$RANGECK+}}',
                ["WRITELN('prefix');", statement, "WRITELN('unreachable');"])
            for opt in OPTS:
                yield (f'domain_fail_{index}_{mathck == "+"}', source,
                       'vintage', opt, (None, 'prefix\n',
                                        f'runtime error: {message}\n'))
    # RANGECK- leaves the domains unchecked; CHAR wraps at its byte.
    source = domain_program('{$RANGECK-}', [
        "ch := CHR(255); WRITELN(ORD(SUCC(ch)));",
        "ch := CHR(0); WRITELN(ORD(PRED(ch)));",
        "s := 10; i := SUCC(s); WRITELN(i);"
    ])
    for opt in OPTS:
        yield 'domain_off', source, 'vintage', opt, (0, '0\n255\n11\n', '')
    # A subrange at its host's extreme: MATHCK's base overflow comes first.
    statement = '  t := 32767; t := SUCC(t);'
    source = domain_program('{$MATHCK+}{$RANGECK+}', [statement.strip()])
    line = source.splitlines().index(statement) + 1
    column = statement.index('SUCC') + 1
    for opt in OPTS:
        yield ('domain_base_first', source, 'vintage', opt,
               (None, '',
                'runtime error: MATHCK signed overflow in SUCC at line '
                f'{line} column {column} (operand=32767)\n'))


def shadow_jobs():
    """A user routine named SUCC or SQR is an ordinary call, never the
    builtin."""
    source = '\n'.join([
        '{$MATHCK+}', 'PROGRAM Shadow;', 'VAR i: INTEGER;',
        'FUNCTION Succ(x: INTEGER): INTEGER; BEGIN Succ := x DIV 2 END;',
        'FUNCTION Sqr(x: INTEGER): INTEGER; BEGIN Sqr := x DIV 4 END;',
        'BEGIN', "  i := 32767; WRITELN(SUCC(i), ' ', PRED(i), ' ', SQR(i), "
        "' ', SQR(-32767), ' ', ABS(-32767))", 'END.'
    ]) + '\n'
    for dialect in ['vintage', 'extended']:
        for opt in OPTS:
            yield 'shadow', source, dialect, opt, (
                0, '16383 32766 8191 -8191 32767\n', '')


def check(work, job):
    tag, source, dialect, opt, (code, stdout, stderr) = job
    result = compile_and_run(work, f'{tag}_{dialect}_{opt}', source, dialect,
                             opt)
    if code is None:
        assert result.returncode != 0, (source, result)
    else:
        assert result.returncode == code, (source, result)
    assert (result.stdout, result.stderr) == (stdout, stderr), (source, opt,
                                                                result)


def check_ir(work):
    """MATHCK- and legacy (snapshot-free) SUCC/PRED/ABS/SQR wrap with plain
    add/sub/mul; MATHCK+ uses the overflow intrinsic."""
    cells = 0
    for dialect, width, unsigned in matrix():
        _, rows = call_rows(width, unsigned)
        expected = ''.join(
            f'{wrap(exact_call(name, value), width, unsigned)}\n'
            for name, value in rows)
        tag = f'ir_{dialect}_{width}_{int(unsigned)}'
        path = work / f'{tag}.pas'
        path.write_text(step_program(width, unsigned, '-', rows))
        built = run([
            'bin/pascal1981', '-S', '--dialect', dialect, '-O0',
            str(path), '-o',
            str(work / f'{tag}.ll')
        ])
        assert built.returncode == 0, built.stderr
        text = (work / f'{tag}.ll').read_text()
        assert 'with.overflow' not in text and 'pas_math_overflow' not in text, text
        typed = typed_ast(step_program(width, unsigned, '+', rows), dialect)
        checked = run(['bin/codegen', '--dialect', dialect], input=typed)
        assert checked.returncode == 0 and 'with.overflow' in checked.stdout, checked.stderr
        legacy = run(['bin/codegen', '--dialect', dialect],
                     input=json.dumps(strip_snapshots(json.loads(typed))))
        assert legacy.returncode == 0, legacy.stderr
        assert 'with.overflow' not in legacy.stdout, legacy.stdout
        ir = work / f'{tag}_legacy.ll'
        ir.write_text(legacy.stdout)
        for opt in OPTS:
            exe = work / f'{tag}_legacy.O{opt}'
            linked = run([
                'clang', f'-O{opt}', '-Wno-override-module',
                str(ir), 'runtime/build/libpascalrt.a', '-lcjson', '-lm', '-o',
                str(exe)
            ])
            assert linked.returncode == 0, linked.stderr
            ran = run([str(exe)])
            assert (ran.returncode, ran.stdout,
                    ran.stderr) == (0, expected, ''), (tag, opt, ran)
            cells += 1
    return cells


def check_constants(work):
    """A fully constant SUCC/PRED/ABS/SQR must fit its type at compile time,
    under either MATHCK setting; a valid one is exact at its context's
    type."""
    cells = 0
    rejects = [
        ('vintage', 'WRITELN(SUCC(M));',
         'Positive integer constant out of range for INTEGER'),
        ('vintage', 'WRITELN(PRED(N));',
         'Negative integer constant out of range for INTEGER'),
        ('vintage', 'i := SUCC(M) - 1;',
         'Positive integer constant out of range for INTEGER'),
        ('extended', 'WRITELN(SUCC(M));',
         'Positive integer constant out of range for INTEGER'),
        ('vintage', 'WRITELN(ABS(N));',
         'Positive integer constant out of range for INTEGER'),
        ('vintage', 'WRITELN(SQR(200));',
         'Positive integer constant out of range for INTEGER'),
        ('vintage', 'i := SQR(-182);',
         'Positive integer constant out of range for INTEGER'),
        ('extended', 'WRITELN(SQR(M));',
         'Positive integer constant out of range for INTEGER'),
        # Beyond INTEGER64: reported, never a trap inside the compiler.
        ('extended', 'g := SQR(3037000500);',
         'Positive integer constant out of range for INTEGER64'),
    ]
    for flag in '+-':
        for index, (dialect, statement, message) in enumerate(rejects):
            source = '\n'.join([
                f'{{$MATHCK{flag}}}', 'PROGRAM Folded;',
                'CONST M = 32767; N = -32768;', 'VAR i: INTEGER;' +
                (' g: INTEGER64;' if dialect == 'extended' else ''), 'BEGIN',
                f'  {statement}', 'END.'
            ]) + '\n'
            path = work / f'const_reject_{index}_{flag == "+"}.pas'
            path.write_text(source)
            built = run([
                'bin/pascal1981', '--dialect', dialect,
                str(path), '-o',
                str(path.with_suffix(''))
            ])
            assert built.returncode != 0 and message in built.stderr, (source,
                                                                       built)
            cells += 1
        source = '\n'.join([
            f'{{$MATHCK{flag}}}', 'PROGRAM Folded;',
            'CONST M = 32767; N = -32768;', 'VAR i: INTEGER; j: INTEGER32;',
            'BEGIN',
            "  i := SUCC(M - 1); WRITELN(i, ' ', PRED(N + 1), ' ', SUCC(SUCC(3)));",
            "  j := SUCC(M); WRITELN(j); j := PRED(N); WRITELN(j);",
            "  i := ABS(N + 1); WRITELN(i, ' ', SQR(-181), ' ', ABS(-5));",
            "  j := ABS(N); WRITELN(j); j := SQR(200); WRITELN(j);", 'END.'
        ]) + '\n'
        for opt in OPTS:
            result = compile_and_run(work, f'const_ok_{flag == "+"}', source,
                                     'extended', opt)
            assert (result.returncode, result.stdout, result.stderr) == (
                0, '32767 -32768 5\n32768\n-32769\n32767 32761 5\n'
                '32768\n40000\n', ''), result
            cells += 1
    return cells


OK_FUNCS = {
    'SADDOK': (False, lambda a, b: a + b),
    'SMULOK': (False, lambda a, b: a * b),
    'UADDOK': (True, lambda a, b: a + b),
    'UMULOK': (True, lambda a, b: a * b),
}
OK_PAIRS = {
    False: [(1, 2), (32767, 1), (32767, 0), (-32768, -1), (-32768, 32767),
            (-1, -1), (181, 181), (182, 182), (-32768, -32768), (-32768, 1),
            (255, -129), (0, -32768)],
    True: [(1, 2), (65535, 1), (65535, 0), (32768, 32768), (255, 257),
           (256, 256), (65535, 65535), (0, 65535), (40000, 2)],
}


def overflow_ok_program(flag, declare):
    """Every IBM *OK function over boundary pairs, printing the BOOLEAN
    result and the wrapped C. declare: '' (builtin) or 'EXTERN' (the
    manual's own declaration, served by libpascalrt)."""
    source = [
        f'{{$MATHCK{flag}}}', 'PROGRAM OkFuncs;', 'VAR s: INTEGER; w: WORD;'
    ]
    if declare:
        source += [
            'FUNCTION UADDOK(A, B: WORD; VAR C: WORD): BOOLEAN; EXTERN;',
            'FUNCTION SADDOK(A, B: INTEGER; VAR C: INTEGER): BOOLEAN; EXTERN;',
            'FUNCTION UMULOK(A, B: WORD; VAR C: WORD): BOOLEAN; EXTERN;',
            'FUNCTION SMULOK(A, B: INTEGER; VAR C: INTEGER): BOOLEAN; EXTERN;'
        ]
    source.append('BEGIN')
    expected = []
    for name, (unsigned, fn) in OK_FUNCS.items():
        target = 'w' if unsigned else 's'
        for a, b in OK_PAIRS[unsigned]:
            exact = fn(a, b)
            low, high = limits(16, unsigned)
            source.append(
                f"  WRITELN({name}({a}, {b}, {target}), ' ', {target});")
            expected.append(f"{'TRUE' if low <= exact <= high else 'FALSE'} "
                            f'{wrap(exact, 16, unsigned)}')
    source.append('END.')
    return '\n'.join(source) + '\n', '\n'.join(expected) + '\n'


def overflow_ok_jobs():
    for dialect in ['vintage', 'extended']:
        for flag in '+-':
            for declare in ['', 'EXTERN']:
                source, expected = overflow_ok_program(flag, declare)
                for opt in OPTS:
                    yield (f'okfn_{flag == "+"}_{declare}', source, dialect,
                           opt, (0, expected, ''))
    # Operands are ordinary expressions; C may be any INTEGER/WORD designator.
    source = '\n'.join([
        '{$MATHCK+}', 'PROGRAM OkDesignators;',
        'TYPE R = RECORD f: INTEGER; g: WORD END;',
        'VAR r: R; a: ARRAY [1..3] OF INTEGER; i: INTEGER;', 'BEGIN',
        '  i := 2; a[i] := 30000;',
        "  WRITELN(SADDOK(a[i], a[i], a[i + 1]), ' ', a[3]);",
        "  WRITELN(UMULOK(WRD(i) * 300, 300, r.g), ' ', r.g);",
        "  WRITELN(SMULOK(-i, 16384, r.f), ' ', r.f);", 'END.'
    ]) + '\n'
    for dialect in ['vintage', 'extended']:
        for opt in OPTS:
            yield ('okfn_designators', source, dialect, opt,
                   (0, 'FALSE -5536\nFALSE 48928\nTRUE -32768\n', ''))
    # A user routine of the same name is an ordinary call.
    source = '\n'.join([
        'PROGRAM OkShadow;', 'VAR c: INTEGER;',
        'FUNCTION SAddOk(A, B: INTEGER; VAR C: INTEGER): BOOLEAN;',
        'BEGIN C := 7; SAddOk := FALSE END;', 'BEGIN',
        "  WRITELN(SADDOK(1, 2, c), ' ', c)", 'END.'
    ]) + '\n'
    for opt in OPTS:
        yield 'okfn_shadow', source, 'vintage', opt, (0, 'FALSE 7\n', '')


NO_CHECK_SOURCE = """{$MATHCK+}
PROGRAM NoCheck;
VAR i, j: INTEGER; w: WORD;
BEGIN
  i := -32768; j := 32767; w := 65535;
  WRITELN(ORD(i), ' ', ORD(j), ' ', WRD(i), ' ', WRD(j));
  WRITELN(ODD(i), ' ', ODD(j), ' ', ORD(HIBYTE(i)), ' ', ORD(LOBYTE(j)), ' ',
          ORD(HIBYTE(w)));
  i := 300; j := -1;
  WRITELN(BYWORD(i, j), ' ', BYWORD(w, w));
  i := -32768;
  WRITELN(FLOAT(i):9:1, ' ', FLOAT(w):8:1);
END.
"""
NO_CHECK_OUT = ('-32768 32767 32768 32767\nFALSE TRUE 128 255 255\n'
                '11519 65535\n -32768.0  65535.0\n')


def no_check_jobs():
    """Builtins the audit (docs/mathck_builtin_audit.md) classifies as
    needing no MATHCK check: defined results at the extremes."""
    for dialect in ['vintage', 'extended']:
        for opt in OPTS:
            yield 'nocheck', NO_CHECK_SOURCE, dialect, opt, (0, NO_CHECK_OUT,
                                                             '')


def check_overflow_ok_static(work):
    """The builtin form never calls the overflow failure; misuse is a
    compile-time error."""
    cells = 0
    nocheck = work / 'nocheck_ir.pas'
    nocheck.write_text(NO_CHECK_SOURCE)
    for dialect in ['vintage', 'extended']:
        built = run([
            'bin/pascal1981', '-S', '--dialect', dialect, '-O0',
            str(nocheck), '-o',
            str(nocheck.with_suffix('.ll'))
        ])
        assert built.returncode == 0, built.stderr
        assert 'pas_math_overflow' not in nocheck.with_suffix(
            '.ll').read_text()
        cells += 1
    path = work / 'okfn_ir.pas'
    path.write_text(overflow_ok_program('+', '')[0])
    for dialect in ['vintage', 'extended']:
        built = run([
            'bin/pascal1981', '-S', '--dialect', dialect, '-O0',
            str(path), '-o',
            str(path.with_suffix('.ll'))
        ])
        assert built.returncode == 0, built.stderr
        text = path.with_suffix('.ll').read_text()
        assert 'pas_math_overflow' not in text and 'with.overflow' in text
        assert '@SADDOK' not in text, 'builtin form must not call the library'
        cells += 1
    rejects = [
        ('SADDOK(1, 2)', 'Argument count mismatch in call to SADDOK'),
        ('SADDOK(1, 2, 3)',
         'VAR argument must be a variable in call to SADDOK'),
        ('SADDOK(1, 2, K)',
         'VAR argument must be a variable in call to SADDOK'),
        ('SADDOK(1, 2, w)', 'VAR argument type mismatch in call to SADDOK'),
        ('UADDOK(1, 2, s)', 'VAR argument type mismatch in call to UADDOK'),
        ('SMULOK(1.5, 2, s)',
         'Argument type mismatch or implicit narrowing in call to SMULOK'),
    ]
    for index, (call, message) in enumerate(rejects):
        source = '\n'.join([
            'PROGRAM OkReject;', 'CONST K = 3;', 'VAR s: INTEGER; w: WORD;',
            'BEGIN', f'  IF {call} THEN WRITELN(s)', 'END.'
        ]) + '\n'
        bad = work / f'okfn_reject_{index}.pas'
        bad.write_text(source)
        built = run(
            ['bin/pascal1981',
             str(bad), '-o',
             str(bad.with_suffix(''))])
        assert built.returncode != 0 and message in built.stderr, (call, built)
        cells += 1
    return cells


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-builtins-') as tmp:
        work = Path(tmp)
        todo = (list(step_jobs()) + list(domain_jobs()) + list(shadow_jobs()) +
                list(overflow_ok_jobs()) + list(no_check_jobs()))
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda job: check(work, job), todo))
        legacy = check_ir(work)
        constants = check_constants(work)
        static = check_overflow_ok_static(work)
    print(
        f'PASS: MATHCK builtins: SUCC/PRED/ABS/SQR {len(todo)} runtime cells (all scalar '
        'widths, both dialects/settings, RANGECK domains, O0-O3); '
        f'{legacy} legacy-AST wrap cells; {constants} constant cells; '
        f'SADDOK/SMULOK/UADDOK/UMULOK builtin and EXTERN forms, {static} '
        'IR/rejection checks')


if __name__ == '__main__':
    main()
