#!/usr/bin/env python3
"""The conformance corpus: raw HTTP requests and what each one probes.

Cases are raw *bytes*, not a dict handed to an HTTP client library, because a
good half of the contract lives in malformed requests -- a non-numeric
Content-Length, a body that stops early, a body that is not valid UTF-8. A
client library would refuse to send most of those.

A case selects the upstream reply by embedding "@@SCENARIO:<name>@@" in the
buffer text; stub_upstream.py reads the marker back out of the prompt. Cases
with no marker get the "ok" scenario.

Every case here is a behaviour the Pascal port has to reproduce exactly. Where
one pins down something surprising, the comment says what and why, so that a
future reader can tell a deliberate contract from an accident.
"""

import json

HOST_HEADER = 'Host: 127.0.0.1\r\n'

# Kept well under the harness's --buffer-limit 1024 so that size-limit cases
# are the only ones that trip it.
SIMPLE_BUFFER = 'PROGRAM Demo;\nVAR i: INTEGER;\nBEGIN\n  FOR i := 1 \nEND.\n'


def _raw(method, path, body_bytes, content_length=None, content_type=True):
    headers = '%s %s HTTP/1.1\r\n%s' % (method, path, HOST_HEADER)
    if content_type:
        headers += 'Content-Type: application/json\r\n'
    if content_length is not None:
        headers += 'Content-Length: %s\r\n' % content_length
    headers += 'Connection: close\r\n\r\n'
    return headers.encode('utf-8') + body_bytes


def _complete(payload_obj, scenario=None):
    """A well-formed POST /complete carrying payload_obj as JSON.

    The marker goes at the *top* of the buffer, and the cursor line moves down
    to compensate. It has to be before the cursor: the proxy sends only the
    text preceding the cursor, so a marker appended at the end of the buffer
    never reaches the backend and every case silently gets the default reply.
    """
    if scenario and isinstance(payload_obj.get('buffer'), str):
        payload_obj = dict(payload_obj)
        payload_obj['buffer'] = ('{ @@SCENARIO:%s@@ }\n' % scenario +
                                 payload_obj['buffer'])
        cursor = dict(payload_obj['cursor'])
        cursor['line'] = cursor['line'] + 1
        payload_obj['cursor'] = cursor
    body = json.dumps(payload_obj).encode('utf-8')
    return _raw('POST', '/complete', body, len(body))


def _payload(buffer_text=SIMPLE_BUFFER,
             goal='finish the loop',
             line=4,
             column=14):
    return {
        'goal': goal,
        'buffer': buffer_text,
        'cursor': {
            'line': line,
            'column': column
        }
    }


CASES = []


def case(name, request, note, capture_upstream=False):
    CASES.append({
        'name': name,
        'request': request,
        'note': note,
        'capture_upstream': capture_upstream
    })


# --------------------------------------------------------------------------
# Happy path and completion post-processing
# --------------------------------------------------------------------------
case('complete_ok',
     _complete(_payload()),
     'The baseline request. Also captures the outgoing upstream payload, '
     'which pins the request shape: two messages, top-level reasoning_effort, '
     'and no "stop" field.',
     capture_upstream=True)

case('complete_no_goal', _complete(_payload(goal='')),
     'An empty goal must not emit a "{  }" comment line before the prefix.')

case(
    'complete_multiline_goal', _complete(_payload(goal='finish\nthe\nloop')),
    'A goal is flattened to one line: newlines become spaces so the goal '
    'stays a single Pascal comment.')

case(
    'complete_fenced', _complete(_payload(), scenario='fenced'),
    'A markdown fence anywhere in the reply is unwrapped, and prose before '
    'it is dropped rather than landing in the buffer.')

case('complete_parts', _complete(_payload(), scenario='parts'),
     'message.content may be a list of {type,text} parts, not just a string.')

case('complete_empty', _complete(_payload(), scenario='empty'),
     'A whitespace-only completion yields "completions": [], never [""].')

case('complete_controls', _complete(_payload(), scenario='controls'),
     'C0 controls and DEL are stripped; \\t and \\n survive.')

case('complete_special_token', _complete(_payload(), scenario='special_token'),
     'Everything from the first "<|" marker onward is discarded.')

case('complete_many_lines', _complete(_payload(), scenario='many_lines'),
     'An 80-line completion is truncated to --max-lines (30).')

case('complete_many_chars', _complete(_payload(), scenario='many_chars'),
     'A 9000-character single line is truncated to 8192 characters.')

# --------------------------------------------------------------------------
# Echo stripping
# --------------------------------------------------------------------------
case(
    'strip_echo_exact',
    _complete(_payload(buffer_text='PROGRAM P;\nBEGIN\nFOR i := 1 TO 10 DO\n',
                       line=3,
                       column=20),
              scenario='echo'),
    'strip_echo pass 1: the reply restates the buffer tail verbatim, an '
    'overlap well over the 5-character floor, so the overlap is removed.')

case(
    'strip_echo_short_overlap_kept',
    _complete(
        _payload(buffer_text='PROGRAM P;\nBEGIN\n  IF x THEN END;\n',
                 line=3,
                 column=18)),
    'A short overlap is structurally required repetition, not an echo. Two '
    'nested blocks legitimately close back to back; stripping "END;" here '
    'was a real bug once, so a <= 5 character overlap must be preserved.')

case(
    'strip_echo_partial_identifier',
    _complete(_payload(buffer_text='PROGRAM P;\nBEGIN\n  DISPO',
                       line=3,
                       column=8),
              scenario='partial'),
    'strip_echo pass 2: the buffer stops mid-identifier ("DISPO") and the '
    'reply opens with the whole word, so only the typed prefix is removed.')

# --------------------------------------------------------------------------
# Cursor handling
# --------------------------------------------------------------------------
case(
    'cursor_clamped_beyond_end', _complete(_payload(line=9999, column=9999)),
    'A cursor past the end of the buffer is clamped, not rejected: it is a '
    'normal race between typing and requesting, not a client error.')

case('cursor_first_position', _complete(_payload(line=1, column=1)),
     'A cursor at the very start yields an empty prefix.')

# --------------------------------------------------------------------------
# Upstream failures -- every one of these is a 502
# --------------------------------------------------------------------------
for _scenario, _why in [
    ('no_choices', 'an empty choices list'),
    ('not_an_object', 'a JSON array where an object was expected'),
    ('null_content', 'a null message.content'),
    ('http_500', 'a non-200 status from the backend'),
    ('malformed', 'a body that is not JSON at all'),
]:
    case(
        'upstream_' + _scenario, _complete(_payload(), scenario=_scenario),
        'Upstream returning %s must surface as a clean 502, never a stack '
        'trace or a 200 with junk in it.' % _why)

case(
    'upstream_reasoning_exhausted',
    _complete(_payload(), scenario='reasoning_exhausted'),
    'finish_reason "length" with empty content but non-empty '
    'reasoning_content is an error, not an empty completion. This is what '
    'makes --reasoning-effort auto calibration able to tell "this effort '
    'value never answers" from "the backend is down".')

case(
    'upstream_timeout', _complete(_payload(), scenario='slow'),
    'The backend stalls past --upstream-timeout, so the proxy gives up '
    'first and reports it, rather than leaving the editor to time out with '
    'no explanation.')

# --------------------------------------------------------------------------
# Routing
# --------------------------------------------------------------------------
case(
    'health_ok', _raw('GET', '/health', b'', content_type=False),
    'GET /health performs a live probe and reports the resolved model and '
    'reasoning_effort.')

case('unknown_get_path', _raw('GET', '/nope', b'', content_type=False),
     'Any GET that is not /health is a 404.')

case('unknown_post_path',
     _complete(_payload()).replace(b'POST /complete', b'POST /nope', 1),
     'Any POST that is not /complete is a 404.')

case('get_on_complete', _raw('GET', '/complete', b'', content_type=False),
     'GET /complete is a 404, not a 405: the GET handler only knows /health.')

# --------------------------------------------------------------------------
# Malformed requests
# --------------------------------------------------------------------------
case(
    'empty_body', _raw('POST', '/complete', b'', 0),
    'A zero-length body is a 413, not a 400. Surprising, but the size gate '
    'runs before any parsing and rejects "<= 0" along with "too large".')

case('missing_content_length', _raw('POST', '/complete', b''),
     'A missing Content-Length reads as zero and takes the same 413 path.')

case('bad_content_length', _raw('POST', '/complete', b'{}', 'abc'),
     'A non-numeric Content-Length is a 400.')

case('body_too_large', _raw('POST', '/complete', b'x' * 4000, 4000),
     'A body over twice --buffer-limit is refused by size before parsing.')

case(
    'truncated_body', _raw('POST', '/complete', b'{"goal":"x"', 200),
    'Content-Length promises more than the client sends, then the socket '
    'closes: the short read is reported rather than hanging.')

case('invalid_json', _raw('POST', '/complete', b'{not json', 9),
     'A body that is not JSON is a 400.')

case('invalid_utf8', _raw('POST', '/complete', b'\xff\xfe\x00bad', 6),
     'A body that is not valid UTF-8 is a 400, not a 500.')

# Schema validation -- each of these is a distinct 400 message.
for _name, _obj, _note in [
    ('schema_not_an_object', [1, 2, 3], 'a JSON array as the whole body'),
    ('schema_buffer_missing', {
        'goal': 'x',
        'cursor': {
            'line': 1,
            'column': 1
        }
    }, 'no "buffer" key at all'),
    ('schema_buffer_not_string', {
        'goal': 'x',
        'buffer': 42,
        'cursor': {
            'line': 1,
            'column': 1
        }
    }, 'a non-string "buffer"'),
    ('schema_goal_not_string', {
        'goal': 42,
        'buffer': 'x',
        'cursor': {
            'line': 1,
            'column': 1
        }
    }, 'a non-string "goal"'),
    ('schema_cursor_missing', {
        'goal': 'x',
        'buffer': 'x'
    }, 'no "cursor" object'),
    ('schema_cursor_not_object', {
        'goal': 'x',
        'buffer': 'x',
        'cursor': 5
    }, 'a non-object "cursor"'),
    ('schema_line_zero', {
        'goal': 'x',
        'buffer': 'x',
        'cursor': {
            'line': 0,
            'column': 1
        }
    }, 'a line number below 1 (the protocol is 1-based)'),
    ('schema_line_bool', {
        'goal': 'x',
        'buffer': 'x',
        'cursor': {
            'line': True,
            'column': 1
        }
    }, 'a boolean line -- rejected even though bool is an int subtype'),
    ('schema_column_bool', {
        'goal': 'x',
        'buffer': 'x',
        'cursor': {
            'line': 1,
            'column': True
        }
    }, 'a boolean column, likewise'),
]:
    _body = json.dumps(_obj).encode('utf-8')
    case(
        _name, _raw('POST', '/complete', _body, len(_body)),
        'Schema validation rejects %s with a 400 naming the offending '
        'field.' % _note)

case(
    'buffer_over_limit', _complete(_payload(buffer_text='A' * 1500)),
    'A buffer over --buffer-limit but under the raw byte gate is rejected '
    'by schema validation, with the limit named in the message.')


def names():
    return [entry['name'] for entry in CASES]


if __name__ == '__main__':
    for entry in CASES:
        print(entry['name'])
    print('\n%d cases' % len(CASES))
