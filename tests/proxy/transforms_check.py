#!/usr/bin/env python3
"""Differential test for proxycore's pure transforms.

Every transform in `src/proxycore.pas` replaces a function in
`tools/pascal1981_completion_proxy.py`. This feeds the same inputs to both and
compares the answers, which is a stronger check than a recorded golden: the
expected values come from the code being replaced, so a case nobody thought
to predict still counts, and the corpus can grow without anyone working out
by hand what the answer should be.

    tests/proxy/transforms_check.py                  # build with bin/pascal1981
    tests/proxy/transforms_check.py path/to/compiler

The corpus deliberately contains no NUL bytes. cJSON hands strings back as
NUL-terminated C strings, so a JSON value containing one is truncated there;
see proxycore.inc. Python's own `sanitize_completion` strips NUL anyway, so
nothing downstream of the parse depends on carrying one.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / 'tools'))

import pascal1981_completion_proxy as proxy  # noqa: E402

# --------------------------------------------------------------------------
# Corpus
# --------------------------------------------------------------------------

_BUFFERS = [
    '',
    'x',
    'abc',
    'abc\n',
    '\n',
    '\n\n\n',
    'PROGRAM Demo;\nVAR i: INTEGER;\nBEGIN\n  FOR i := 1 \nEND.\n',
    'line one\r\nline two\r\n',
    '  indented\n\ttabbed\n',
    'héllo wörld\nsecond ligne\n',
    'αβγδε\nζηθ\n',
    'emoji 🙂 here\nand after\n',
    'trailing spaces   \nnext\n',
]

_CURSORS = [
    (1, 1),
    (1, 2),
    (1, 100),
    (2, 1),
    (2, 3),
    (3, 5),
    (4, 14),
    (5, 1),
    (9999, 9999),
    (0, 0),
    (-3, -7),
    (1, 0),
]

_GOALS = [
    '',
    '   ',
    '\n\n',
    'finish the loop',
    '  finish the loop  ',
    'first line\nsecond line',
    'a } brace and a { brace',
    'unicode gôal',
]

_GRAMMARS = [
    '',
    '   \n  ',
    'program = "PROGRAM" ident ";" block "." ;',
    '\n  leading and trailing whitespace  \n',
    'rule = { "a" } | (* comment *) "b" ;',
]

_FENCE_TEXTS = [
    'plain text, no fence',
    '```\ncode here\n```',
    '```pascal\n  i := i + 1;\n```',
    'Here you go:\n```pascal\n  i := i + 1;\n```\nHope that helps.',
    '```pascal\nunterminated block',
    '```',
    'prose then ```',
    '```\n```',
    '```\n\n  spaced  \n\n```',
    'text with ``` in the middle\nand more after',
    '````\nfour ticks\n````',
]

_SANITIZE_TEXTS = [
    '',
    'plain',
    '\n\n\nleading blanks',
    'trailing spaces   ',
    'a\rb\x1bc\x00d'.replace('\x00', ''),
    'ctrl \x01\x02\x1f and \x7f del',
    'tab\tkept\nnewline kept',
    'marker <|channel|> after',
    '<|channel|>only a marker',
    'before <| truncated',
    '\n'.join('line %d' % i for i in range(60)),
    '\n'.join('line %d' % i for i in range(60)) + '\n',
    'X' * 9000,
    'é' * 5000,
    '\n\n' + '\n'.join('l%d' % i for i in range(5)),
]

_MAX_LINES = [1, 0, -5, 3, 30, 1000]


def _payload(**overrides):
    payload = {
        'goal': 'finish the loop',
        'buffer': 'PROGRAM Demo;\nVAR i: INTEGER;\n',
        'cursor': {
            'line': 2,
            'column': 3
        },
    }
    payload.update(overrides)
    return payload


_PAYLOADS = [
    _payload(),
    _payload(goal=''),
    _payload(buffer=''),
    _payload(buffer='A' * 200),
    _payload(cursor={
        'line': 1,
        'column': 1
    }),
    _payload(cursor={
        'line': 9999,
        'column': 9999
    }),
    [1, 2, 3],
    'a bare string',
    42,
    None,
    {},
    {
        'buffer': 'x'
    },
    {
        'goal': 'x',
        'cursor': {
            'line': 1,
            'column': 1
        }
    },
    _payload(buffer=42),
    _payload(buffer=None),
    _payload(goal=42),
    _payload(goal=None),
    {
        'goal': 'x',
        'buffer': 'x'
    },
    _payload(cursor=5),
    _payload(cursor=None),
    _payload(cursor={'column': 1}),
    _payload(cursor={'line': 1}),
    _payload(cursor={
        'line': 0,
        'column': 1
    }),
    _payload(cursor={
        'line': 1,
        'column': 0
    }),
    _payload(cursor={
        'line': -4,
        'column': 1
    }),
    _payload(cursor={
        'line': True,
        'column': 1
    }),
    _payload(cursor={
        'line': 1,
        'column': True
    }),
    _payload(cursor={
        'line': False,
        'column': 1
    }),
    _payload(cursor={
        'line': 'two',
        'column': 1
    }),
    _payload(cursor={
        'line': 1,
        'column': 'three'
    }),
    _payload(cursor={
        'line': 1.5,
        'column': 1
    }),
    _payload(cursor={
        'line': None,
        'column': 1
    }),
    _payload(buffer='héllo'),
]

_BUFFER_LIMITS = [65536, 100, 5, 1]


def _choice(content, finish_reason='stop', extra=None):
    message = {'role': 'assistant', 'content': content}
    if extra:
        message.update(extra)
    return {'index': 0, 'message': message, 'finish_reason': finish_reason}


_RESPONSES = [
    {
        'model': 'm',
        'id': 'r1',
        'choices': [_choice('  i := i + 1;')]
    },
    {
        'model': 'm',
        'id': 'r1',
        'choices': [_choice('')]
    },
    {
        'choices': [_choice('no model or id')]
    },
    {
        'model': 42,
        'id': 7,
        'choices': [_choice('bad metadata types')]
    },
    {
        'model': None,
        'id': None,
        'choices': [_choice('null metadata')]
    },
    {
        'model':
        'm',
        'choices': [
            _choice([{
                'type': 'text',
                'text': 'alpha'
            }, {
                'type': 'text',
                'text': 'beta'
            }])
        ]
    },
    {
        'model': 'm',
        'choices': [_choice([])]
    },
    {
        'model': 'm',
        'choices': [_choice([{
            'type': 'image'
        }])]
    },
    {
        'model': 'm',
        'choices': [_choice([{
            'type': 'text',
            'text': 42
        }])]
    },
    {
        'model': 'm',
        'choices': [_choice(['a bare string part'])]
    },
    {
        'model': 'm',
        'choices': [_choice(None)]
    },
    {
        'model': 'm',
        'choices': [_choice(42)]
    },
    {
        'model': 'm',
        'choices': [{
            'index': 0
        }]
    },
    {
        'model': 'm',
        'choices': [{
            'index': 0,
            'message': 'not an object'
        }]
    },
    {
        'model': 'm',
        'choices': ['not an object']
    },
    {
        'model': 'm',
        'choices': []
    },
    {
        'model': 'm',
        'choices': 'not a list'
    },
    {
        'model': 'm'
    },
    [1, 2, 3],
    'a bare string',
    42,
    None,
    {
        'model': 'm',
        'choices': [_choice('', 'length', {'reasoning_content': 'thinking'})]
    },
    {
        'model': 'm',
        'choices': [_choice('', 'stop', {'reasoning_content': 'thinking'})]
    },
    {
        'model': 'm',
        'choices': [_choice('', 'length', {'reasoning_content': ''})]
    },
    {
        'model': 'm',
        'choices': [_choice('', 'length')]
    },
    {
        'model':
        'm',
        'choices':
        [_choice('answered', 'length', {'reasoning_content': 'thinking'})]
    },
    {
        'model': 'm',
        'choices': [_choice('```pascal\n  fenced();\n```')]
    },
]

_ECHO_BUFFER_DISPO = ('PROGRAM D;\n'
                      'VAR p1, p2: ^INTEGER;\n'
                      'BEGIN\n'
                      '  NEW(p1); NEW(p2);\n'
                      '  DISPOSE(p1);\n'
                      '  DISPO')

# Pairs taken straight from the Python suite's own echo tests, which encode
# the false positives that shaped the floors.
_ECHO_PAIRS = [
    ('VAR x: INTEGER;\nBEGIN\n', '  x := 1;'),
    ('BEGIN\n  BEGIN\n    x := 1\n  END;\n', 'END;\nEND.'),
    ('PROGRAM Demo;\nBEGIN\n  x := ', 'BEGIN\n  x := 1;\nEND.'),
    (';;;;;', ';;;;;y'),
    ('xxxxxx', 'xxxxxxy'),
    ('...\nBEGIN OF SOMETHING\n', 'begin of something\n  x := 1;'),
    ('PROGRAM Demo;\nBEGIN\n  x := 1;\n', '  x := 1;\n'),
    ('', 'x := 1;'),
    ('BEGIN\n', ''),
    ('', ''),
    ('PROGRAM Demo;\nBEGIN\n  x := 1;\n', '  x := 1;\n  y := 2;'),
    (_ECHO_BUFFER_DISPO, 'DISPOSE(p2);\nEND.'),
    (_ECHO_BUFFER_DISPO, 'SE(p2);\nEND.'),
    (_ECHO_BUFFER_DISPO, 'dispose(p2);'),
    (_ECHO_BUFFER_DISPO[:-5] + 'dispo', 'DISPOSE(p2);'),
    ('BEGIN\n  x', 'x := 1;'),
    ('FOR i := 1 TO 1', '10 DO'),
    (_ECHO_BUFFER_DISPO, 'WRITELN(x);'),
    (_ECHO_BUFFER_DISPO + 'SE', 'DISP'),
    ('  DISPOSE(', 'p2);'),
    ('FOR i := 1 ', 'TO 10 DO'),
    ('BEGIN\n  x := 1;\n', 'END;'),
]

# The approximate pass has no coverage at all in the Python suite, so it gets
# the most here. Each snippet's tail is retyped the way a small model
# actually does it -- reindented, re-cased, with a renamed variable or a
# dropped token -- and then continued, which is exactly the shape an exact
# match cannot see.
_ECHO_TAILS = [
    'PROGRAM Demo;\nVAR i, total: INTEGER;\nBEGIN\n  total := 0;\n'
    '  FOR i := 1 TO 10 DO\n    total := total + i;\n',
    'PROCEDURE Walk(p: Node);\nBEGIN\n  WHILE p <> NIL DO\n'
    '  BEGIN\n    WRITELN(p^.value);\n    p := p^.next;\n  END;\n',
    'BEGIN\n  READLN(n);\n  IF n > 0 THEN\n    WRITELN(n)\n  ELSE\n',
    'CONST LIMIT = 100;\nVAR count: INTEGER;\nBEGIN\n  count := 0;\n',
]

_ECHO_CONTINUATIONS = ['\n  WRITELN(total);\nEND.', '', '\nEND.']


def _retype(text, mode):
    """Retype TEXT the way a small model does when it echoes."""
    if mode == 'exact':
        return text
    if mode == 'reindent':
        return '\n'.join(line.strip() for line in text.split('\n'))
    if mode == 'recase':
        return text.swapcase()
    if mode == 'rename':
        return text.replace('total', 'sum').replace('count', 'n')
    if mode == 'drop':
        parts = text.split(' ')
        return ' '.join(parts[:3] + parts[4:]) if len(parts) > 4 else text
    if mode == 'reindent_recase':
        return '\n'.join(line.strip().swapcase() for line in text.split('\n'))
    raise AssertionError(mode)


_ECHO_MODES = [
    'exact', 'reindent', 'recase', 'rename', 'drop', 'reindent_recase'
]


def _echo_pairs():
    pairs = list(_ECHO_PAIRS)
    for snippet in _ECHO_TAILS:
        for tail_lines in (1, 2, 3):
            lines = snippet.rstrip('\n').split('\n')
            tail = '\n'.join(lines[-tail_lines:])
            for mode in _ECHO_MODES:
                for continuation in _ECHO_CONTINUATIONS:
                    pairs.append((snippet, _retype(tail, mode) + continuation))
    return pairs


def build_corpus():
    """Return (jobs, expectations) as parallel lists."""
    jobs = []
    expected = []

    def add(job, want):
        jobs.append(job)
        expected.append(want)

    add({'op': 'system_prompt'}, {'text': proxy.SYSTEM_PROMPT})

    for buffer in _BUFFERS:
        for line, column in _CURSORS:
            add(
                {
                    'op': 'compute_prefix',
                    'buffer': buffer,
                    'line': line,
                    'column': column
                }, {'prefix': proxy.compute_prefix(buffer, line, column)})

    for goal in _GOALS:
        for prefix in ['', 'PROGRAM p;\n', 'x']:
            for grammar in _GRAMMARS:
                add(
                    {
                        'op': 'build_prompt',
                        'goal': goal,
                        'prefix': prefix,
                        'grammar': grammar
                    }, {'prompt': proxy.build_prompt(goal, prefix, grammar)})

    for text in _FENCE_TEXTS:
        add({
            'op': 'strip_code_fence',
            'text': text
        }, {'text': proxy._strip_code_fence(text)})

    for text in _SANITIZE_TEXTS:
        for max_lines in _MAX_LINES:
            add({
                'op': 'sanitize',
                'text': text,
                'max_lines': max_lines
            }, {'text': proxy.sanitize_completion(text, max_lines)})

    for payload in _PAYLOADS:
        for limit in _BUFFER_LIMITS:
            job = {
                'op': 'validate_request',
                'payload': payload,
                'buffer_limit': limit
            }
            try:
                goal, buffer, line, column = proxy.validate_request(
                    payload, limit)
            except proxy.RequestError as exc:
                add(job, {'ok': 'no', 'error': str(exc)})
            else:
                add(
                    job, {
                        'ok': 'yes',
                        'goal': goal,
                        'buffer': buffer,
                        'line': line,
                        'column': column
                    })

    for buffer, candidate in _echo_pairs():
        add({
            'op': 'strip_echo',
            'buffer': buffer,
            'candidate': candidate
        }, {'text': proxy.strip_echo(buffer, candidate)})

    for response in _RESPONSES:
        job = {'op': 'extract_completion', 'response': response}
        try:
            text, model, request_id = proxy.extract_completions(response)
        except proxy.ReasoningBudgetExhausted as exc:
            add(job, {'outcome': 2, 'error': str(exc)})
        except proxy.UpstreamError as exc:
            add(job, {'outcome': 1, 'error': str(exc)})
        else:
            add(
                job, {
                    'outcome': 0,
                    'text': text,
                    'model': model,
                    'request_id': request_id
                })

    return jobs, expected


# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------


def main() -> int:
    compiler = sys.argv[1] if len(sys.argv) > 1 else str(REPO / 'bin' /
                                                         'pascal1981')
    jobs, expected = build_corpus()

    with tempfile.TemporaryDirectory() as work:
        binary = str(Path(work) / 'transforms')
        subprocess.run([str(HERE / 'transforms.build.sh'), compiler, binary],
                       cwd=HERE,
                       check=True)
        completed = subprocess.run([binary],
                                   input=json.dumps(jobs).encode('utf-8'),
                                   stdout=subprocess.PIPE,
                                   check=True)

    actual = json.loads(completed.stdout.decode('utf-8'))
    if len(actual) != len(expected):
        print('transforms: got %d results for %d jobs' %
              (len(actual), len(expected)),
              file=sys.stderr)
        return 1

    failures = 0
    for job, want, got in zip(jobs, expected, actual):
        if got != want:
            failures += 1
            if failures <= 20:
                print('MISMATCH %s' % job.get('op'))
                print('  job:      %s' % json.dumps(job)[:400])
                print('  expected: %s' % json.dumps(want)[:400])
                print('  actual:   %s' % json.dumps(got)[:400])

    print('transforms: %d cases, %d mismatches' % (len(expected), failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
