#!/usr/bin/env python3
"""MATHCK+ scalar overflow enforcement and defined MATHCK- wrapping.

Oracles come from exact integer arithmetic, never from a previous compiler's
output. Every runtime cell runs at O0-O3.
"""
import json
import re
import resource
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPTS = range(4)
SYMBOL = {
    'PLUS': '+',
    'MINUS': '-',
    'MUL': '*',
    'DIV': 'DIV',
    'MOD': 'MOD',
    'NEG': '-'
}


def run(cmd, **kwargs):
    return subprocess.run(cmd,
                          cwd=ROOT,
                          text=True,
                          capture_output=True,
                          timeout=60,
                          **kwargs)


def type_name(width, unsigned):
    base = 'WORD' if unsigned else 'INTEGER'
    return base if width == 16 else f'{base}{width}'


def limits(width, unsigned):
    if unsigned:
        return 0, (1 << width) - 1
    return -(1 << (width - 1)), (1 << (width - 1)) - 1


def exact(op, left, right):
    if op == 'NEG':
        return -left
    if op in ('DIV', 'MOD'):
        # Truncating division; MOD has the dividend's sign.
        quotient = abs(left) // abs(right)
        if (left < 0) != (right < 0):
            quotient = -quotient
        return quotient if op == 'DIV' else left - quotient * right
    return {
        'PLUS': left + right,
        'MINUS': left - right,
        'MUL': left * right
    }[op]


def wrap(value, width, unsigned):
    value &= (1 << width) - 1
    if not unsigned and value >= 1 << (width - 1):
        value -= 1 << width
    return value


def setup(names):
    """Statements giving each name its value at run time.

    Values beyond 2^53 are built from 32-bit halves: INTEGER64 literals above
    2^53 lose precision (a separately recorded literal gap). No step
    overflows the variable's own type."""
    out = []
    for name, value in names.items():
        if abs(value) <= 1 << 53:
            out.append(f'{name} := {value};')
        else:
            out += [
                f'{name} := {value >> 32};', f'{name} := {name} * 4294967296;',
                f'{name} := {name} + {value & 0xFFFFFFFF};'
            ]
    return out


def cases(width, unsigned):
    """(op, left, right) pairs whose exact result overflows."""
    low, high = limits(width, unsigned)
    if unsigned:
        # Only zero negates without unsigned overflow.
        return [('PLUS', high, 1), ('MINUS', 0, 1), ('MUL', high, 2),
                ('NEG', 1, None), ('NEG', high, None)]
    return [('PLUS', high, 1), ('PLUS', low, -1), ('MINUS', low, 1),
            ('MINUS', high, -1), ('MUL', high, 2), ('MUL', low, -1),
            ('DIV', low, -1), ('NEG', low, None)]


def successes(width, unsigned):
    """In-range results at the boundaries; signed MIN is ordinary data."""
    low, high = limits(width, unsigned)
    if unsigned:
        return [('PLUS', high - 1, 1), ('MINUS', 1, 1), ('MINUS', high, high),
                ('MUL', high, 1), ('MUL', high >> 1, 2), ('PLUS', 0, 0),
                ('DIV', high, 1), ('MOD', high, 2), ('NEG', 0, None)]
    return [('PLUS', high - 1, 1), ('MINUS', low + 1, 1),
            ('PLUS', low + 1, -1), ('MUL', low >> 1, 2), ('MUL', high, -1),
            ('MUL', low, 1), ('MINUS', -1, high), ('PLUS', low, high),
            ('MOD', low, -1), ('DIV', low, 1), ('DIV', low + 1, -1),
            ('DIV', low, 2), ('MOD', low, 2), ('NEG', high, None),
            ('NEG', low + 1, None), ('NEG', 0, None)]


def program(width, unsigned, flag, rows, body_prefix=()):
    tk = type_name(width, unsigned)
    names, lines = {}, []
    for index, (op, left, right) in enumerate(rows):
        names[f'l{index}'] = left
        if op == 'NEG':
            lines.append(f'WRITELN(- l{index});')
        else:
            names[f'r{index}'] = right
            lines.append(f'WRITELN(l{index} {SYMBOL[op]} r{index});')
    decl = ', '.join(names) or 'unused'
    source = [
        f'{{$MATHCK{flag}}}', 'PROGRAM Overflow;', f'VAR {decl}: {tk};',
        'BEGIN'
    ]
    source += setup(names) + list(body_prefix) + lines
    source.append('END.')
    return '\n'.join(source) + '\n'


def failure_program(width, unsigned, op, left, right):
    tk = type_name(width, unsigned)
    source = [
        '{$MATHCK+}', 'PROGRAM OverflowFailure;', f'VAR gl, gr: {tk};',
        f'FUNCTION L: {tk}; BEGIN WRITELN(\'left\'); L := gl END;',
        f'FUNCTION R: {tk}; BEGIN WRITELN(\'right\'); R := gr END;', 'BEGIN'
    ]
    source += setup({'gl': left, 'gr': 0 if right is None else right})
    source += ["WRITELN('prefix');"]
    if op == 'NEG':
        call = '  WRITELN(- L);'
        column = call.index('-') + 1
        operands = f'operand={left}'
        stdout = 'prefix\nleft\n'
    else:
        call = f'  WRITELN(L {SYMBOL[op]} R);'
        column = call.index(SYMBOL[op], call.index('L ')) + 1
        operands = f'left={left}, right={right}'
        stdout = 'prefix\nleft\nright\n'
    line = len(source) + 1
    source += [call, "  WRITELN('unreachable')", 'END.']
    sign = 'unsigned' if unsigned else 'signed'
    stderr = (f'runtime error: MATHCK {sign} overflow in {SYMBOL[op]} at line '
              f'{line} column {column} ({operands})\n')
    return '\n'.join(source) + '\n', stdout, stderr


def compile_and_run(work, tag, source, dialect, opt):
    path = work / f'{tag}.pas'
    exe = work / f'{tag}.O{opt}'
    path.write_text(source)
    built = run([
        'bin/pascal1981', '--dialect', dialect, f'-O{opt}',
        str(path), '-o',
        str(exe)
    ])
    assert built.returncode == 0, (source, built.stderr)
    return run([str(exe)])


def matrix():
    for dialect, widths in [('vintage', [16]), ('extended', [8, 16, 32, 64])]:
        for width in widths:
            for unsigned in [False, True]:
                yield dialect, width, unsigned


def jobs(work):
    for dialect, width, unsigned in matrix():
        key = f'{dialect}_{width}_{int(unsigned)}'
        rows = successes(width, unsigned)
        expected = ''.join(f'{exact(*row)}\n' for row in rows)
        for flag in ['+', '-']:
            source = program(width, unsigned, flag, rows)
            for opt in OPTS:
                yield (f'ok_{key}_{flag == "+"}', source, dialect, opt,
                       (0, expected, ''))
        # MATHCK-: every overflowing case wraps at the result width.
        rows = cases(width, unsigned)
        expected = ''.join(f'{wrap(exact(*row), width, unsigned)}\n'
                           for row in rows)
        source = program(width, unsigned, '-', rows)
        for opt in OPTS:
            yield f'wrap_{key}', source, dialect, opt, (0, expected, '')
        for index, (op, left, right) in enumerate(cases(width, unsigned)):
            source, stdout, stderr = failure_program(width, unsigned, op, left,
                                                     right)
            for opt in OPTS:
                yield (f'fail_{key}_{index}', source, dialect, opt,
                       (None, stdout, stderr))


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


def typed_ast(source, dialect):
    text = source
    for stage in ['lexer', 'parser', 'typechecker']:
        cmd = [f'bin/{stage}']
        if stage != 'lexer':
            cmd += ['--dialect', dialect]
        result = run(cmd, input=text)
        assert result.returncode == 0, result.stderr
        text = result.stdout
    return text


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


def unchecked_ir(text):
    # Defined wrapping: plain instructions, no overflow intrinsic or failure
    # path, and no nsw/nuw/poison that would let LLVM assume no overflow.
    assert 'with.overflow' not in text and 'pas_math_overflow' not in text
    assert not re.search(r'= (?:add|sub|mul) (?:nsw|nuw)', text), text
    assert 'poison' not in text and 'undef' not in text
    assert re.search(r'= (?:add|sub|mul) i(?:8|16|32|64) ', text), text


def check_disabled(work):
    """MATHCK- and legacy (snapshot-free) ASTs both get defined wrapping."""
    cells = 0
    for dialect, width, unsigned in matrix():
        rows = cases(width, unsigned)
        expected = ''.join(f'{wrap(exact(*row), width, unsigned)}\n'
                           for row in rows)
        tag = f'disabled_{dialect}_{width}_{int(unsigned)}'
        path = work / f'{tag}.pas'
        path.write_text(program(width, unsigned, '-', rows))
        built = run([
            'bin/pascal1981', '-S', '--dialect', dialect, '-O0',
            str(path), '-o',
            str(work / f'{tag}.ll')
        ])
        assert built.returncode == 0, built.stderr
        unchecked_ir((work / f'{tag}.ll').read_text())
        # The MATHCK+ source with its snapshots removed is a legacy AST: it
        # must wrap like MATHCK-, never inherit the enabled source default.
        typed = typed_ast(program(width, unsigned, '+', rows), dialect)
        assert re.search(r'"mathck":\s*true', typed)
        for ast, checked in [(typed, True),
                             (json.dumps(strip_snapshots(json.loads(typed))),
                              False)]:
            result = run(['bin/codegen', '--dialect', dialect], input=ast)
            assert result.returncode == 0, result.stderr
            if checked:
                assert 'with.overflow' in result.stdout
                continue
            unchecked_ir(result.stdout)
            ir = work / f'{tag}_legacy.ll'
            ir.write_text(result.stdout)
            for opt in OPTS:
                exe = work / f'{tag}_legacy.O{opt}'
                linked = run([
                    'clang', f'-O{opt}', '-Wno-override-module',
                    str(ir), 'runtime/build/libpascalrt.a', '-lcjson', '-lm',
                    '-o',
                    str(exe)
                ])
                assert linked.returncode == 0, linked.stderr
                ran = run([str(exe)])
                assert (ran.returncode, ran.stdout,
                        ran.stderr) == (0, expected, ''), (tag, opt, ran)
                cells += 1
    return cells


def blocks(function):
    """Map each basic-block label of one IR function to its lines."""
    out, label = {}, 'entry'
    for line in function.splitlines()[1:]:
        match = re.match(r'^([-\w.]+):', line)
        if match:
            label = match[1]
        elif line.strip() and line.strip() != '}':
            out.setdefault(label, []).append(line.strip())
    return out


def check_guard_ir(work):
    """O0: each check branches to a noreturn failure before its result is
    extracted, stored or used; checked DIV divides only after both tests."""
    checks = 0
    for dialect, width, unsigned in matrix():
        tk = type_name(width, unsigned)
        source = [
            '{$MATHCK+}', 'PROGRAM Guards;', f'VAR a, b, k: {tk};', 'BEGIN',
            'a := 3; b := 2;', 'k := a + b; k := a - b; k := a * b;',
            'k := a DIV b; k := -a; WRITELN(k)', 'END.'
        ]
        path = work / f'guards_{dialect}_{tk}.pas'
        path.write_text('\n'.join(source) + '\n')
        ir = path.with_suffix('.ll')
        built = run([
            'bin/pascal1981', '-S', '--dialect', dialect, '-O0',
            str(path), '-o',
            str(ir)
        ])
        assert built.returncode == 0, built.stderr
        text = ir.read_text()
        main = re.search(r'define i32 @main.*?\n}', text, re.S)[0]
        graph = blocks(main)
        seen = 0
        for label, lines in graph.items():
            for line in lines:
                call = re.match(
                    r'(%[-\w.]+) = call \{ i\d+, i1 \} @llvm\.[su](?:add|sub|mul)'
                    r'\.with\.overflow\.i(\d+)', line)
                if not call:
                    continue
                pair, bits = call.groups()
                assert bits == str(width), line
                flag = [
                    item for item in lines if re.match(
                        re.escape('%') + r'[-\w.]+ = extractvalue .* ' +
                        re.escape(pair) + r', 1$', item)
                ]
                assert len(flag) == 1, (label, lines)
                flag_name = flag[0].split(' = ')[0]
                branch = lines[-1]
                target = re.fullmatch(
                    r'br i1 ' + re.escape(flag_name) +
                    r', label %(math\.bad\d*), label %(math\.ok\d*)', branch)
                assert target, (label, branch)
                bad, ok = target.groups()
                assert any('call void @pas_math_overflow(' in item
                           for item in graph[bad]), graph[bad]
                assert graph[bad][-1] == 'unreachable', graph[bad]
                # The result is extracted only on the success path.
                result = re.escape(pair) + r', 0$'
                assert not any(re.search(result, item) for item in lines)
                assert any(re.search(result, item) for item in graph[ok])
                seen += 1
            for index, line in enumerate(lines):
                if re.search(r'= (?:sdiv|udiv) ', line):
                    assert label.startswith(
                        'math.ok' if not unsigned else 'div.ok'), (label,
                                                                   lines)
                    seen += 1
        if not unsigned:
            assert re.search(
                r'br i1 %div\.min, label %math\.bad\d*, label %math\.ok', main)
        # + - * and negation are intrinsic checks; DIV is one division.
        assert seen == 5, (dialect, tk, seen, main)
        checks += 1
    return checks


def check_twin(work):
    """A program that never overflows prints the same under both settings."""
    fixture = ROOT / 'tests/fixtures/mathck/twin_arith.pas'
    expected = fixture.with_suffix('.out').read_text()
    cells = 0
    for dialect in ['vintage', 'extended']:
        for flag in ['+', '-']:
            source = f'{{$MATHCK{flag}}}\n' + fixture.read_text()
            for opt in OPTS:
                result = compile_and_run(work, f'twin_{dialect}_{flag == "+"}',
                                         source, dialect, opt)
                assert (result.returncode, result.stdout,
                        result.stderr) == (0, expected, ''), (dialect, flag,
                                                              opt, result)
                cells += 1
    return cells


CONSTANT_PROLOGUE = """PROGRAM Constants;
CONST M = 32767; N = -32768;
VAR i, k: INTEGER; w: WORD;{wide}
BEGIN
  i := 5; w := 1;
"""

# Fully constant operations: rejected at their own (context) type at every
# node, under either MATHCK setting (G23), never wrapped or trapped at run time.
CONSTANT_REJECTS = [
    ('both', 'WRITELN(32767 + 1)', 'Positive', 'INTEGER'),
    ('both', 'WRITELN(N - 1)', 'Negative', 'INTEGER'),
    ('both', 'WRITELN(-N)', 'Positive', 'INTEGER'),
    ('both', 'WRITELN(N DIV (0 - 1))', 'Positive', 'INTEGER'),
    ('both', 'k := i + (M + 1)', 'Positive', 'INTEGER'),
    ('both', 'k := i * (300 * 300)', 'Positive', 'INTEGER'),
    ('both', 'k := (M + 1) - 1', 'Positive', 'INTEGER'),
    ('both', 'IF k > M + 1 THEN WRITELN(1)', 'Positive', 'INTEGER'),
    ('extended', 'b := b + (100 + 100)', 'Positive', 'INTEGER8'),
    ('extended', 'j := j + (2147483647 + 1)', 'Positive', 'INTEGER32'),
    # Exact values beyond INTEGER64: the (checked) compiler's own folder
    # must report them, not trap.
    ('extended', 'g := 3037000500 * 3037000500', 'Positive', 'INTEGER64'),
    ('extended', 'g := (0 - 3037000500) * 3037000500', 'Negative',
     'INTEGER64'),
    # Sign minus applies to the product, which overflows positively.
    ('extended', 'g := -3037000500 * 3037000500', 'Positive', 'INTEGER64'),
    ('extended', 'g := 4611686018427387904 + 4611686018427387904', 'Positive',
     'INTEGER64'),
    ('extended', 'g := -4611686018427387904 - 4611686018427387904 - 1',
     'Negative', 'INTEGER64'),
    ('extended', 'g := ((0 - 4611686018427387904) * 2) DIV (0 - 1)',
     'Positive', 'INTEGER64'),
    ('extended', 'g := -((0 - 4611686018427387904) * 2)', 'Positive',
     'INTEGER64'),
]

# Exact constants at the context type, identical under both settings.
CONSTANT_VALUES = [
    ('both', 'k := -32768; WRITELN(k)', '-32768'),
    ('both', 'WRITELN(-32767 - 1)', '-32768'),
    ('both', 'k := (M - 1) + 1; WRITELN(k)', '32767'),
    ('both', 'w := 0 - 1; WRITELN(w)', '65535'),
    ('both', 'WRITELN(40000 + 1)', '40001'),
    ('extended', 'j := M + 1; WRITELN(j)', '32768'),
    ('extended', 'j := i + (M + 1); WRITELN(j)', '32773'),
    ('extended', 'g := (0 - 4611686018427387904) * 2; WRITELN(g)',
     '-9223372036854775808'),
    ('extended', 'g := 3037000499 * 3037000499; WRITELN(g)',
     '9223372030926249001'),
    ('extended',
     'g := ((0 - 4611686018427387904) * 2) MOD (0 - 1); WRITELN(g)', '0'),
]


def constant_source(dialect, flag, statement):
    wide = (' b: INTEGER8; j: INTEGER32; g: INTEGER64;'
            if dialect == 'extended' else '')
    return (f'{{$MATHCK{flag}}}\n' + CONSTANT_PROLOGUE.format(wide=wide) +
            f'  {statement}\nEND.\n')


def check_constants(work):
    cells = 0
    for dialect in ['vintage', 'extended']:
        for flag in ['+', '-']:
            for scope, statement, sign, tk in CONSTANT_REJECTS:
                if scope != 'both' and scope != dialect:
                    continue
                path = work / f'const_reject_{dialect}_{flag == "+"}_{cells}.pas'
                path.write_text(constant_source(dialect, flag, statement))
                out = path.with_suffix('.ll')
                result = run([
                    'bin/pascal1981', '-S', '--dialect', dialect,
                    str(path), '-o',
                    str(out)
                ])
                assert result.returncode != 0, (statement, result)
                # Exactly one report: an enclosing node does not repeat it.
                assert (result.stderr.count(' integer constant out of range')
                        == 1 and f'{sign} integer constant out of range for '
                        f'{tk}' in result.stderr), (statement, result.stderr)
                assert not out.exists() or not out.read_text(), statement
                cells += 1
            for scope, statement, value in CONSTANT_VALUES:
                if scope != 'both' and scope != dialect:
                    continue
                source = constant_source(dialect, flag, statement)
                for opt in OPTS:
                    result = compile_and_run(
                        work, f'const_ok_{dialect}_{flag == "+"}_{cells}',
                        source, dialect, opt)
                    assert (result.returncode, result.stdout,
                            result.stderr) == (0, value + '\n',
                                               ''), (statement, opt, result)
                    cells += 1
            # A partially constant operation is checked at run time: the
            # constant operand fits, the operation overflows.
            statement = 'k := i + (M - 4); WRITELN(k)'
            source = constant_source(dialect, flag, statement)
            line = source.splitlines().index(f'  {statement}') + 1
            column = f'  {statement}'.index('+') + 1
            for opt in OPTS:
                result = compile_and_run(
                    work, f'const_partial_{dialect}_{flag == "+"}', source,
                    dialect, opt)
                if flag == '+':
                    assert result.returncode != 0, result
                    assert result.stderr == (
                        'runtime error: MATHCK signed overflow in + at line '
                        f'{line} column {column} (left=5, right=32763)\n'
                    ), result
                else:
                    assert (result.returncode,
                            result.stdout) == (0, '-32768\n'), result
                cells += 1
    return cells


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix='mathck-overflow-') as tmp:
        work = Path(tmp)
        todo = list(jobs(work))
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda job: check(work, job), todo))
        legacy = check_disabled(work)
        guards = check_guard_ir(work)
        twins = check_twin(work)
        constants = check_constants(work)
    print(
        f'PASS: MATHCK + - * DIV and unary - overflow: {len(todo)} runtime cells, '
        'all scalar widths, both dialects/settings, O0-O3; MATHCK- IR has no '
        f'overflow flags; {legacy} legacy-AST wrap cells; {guards} O0 '
        f'guard-order programs; {twins} on/off twin cells; {constants} '
        'constant-operand cells')


if __name__ == '__main__':
    main()
