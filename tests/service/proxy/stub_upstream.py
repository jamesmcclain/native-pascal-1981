#!/usr/bin/env python3
"""Deterministic stand-in for an OpenAI-compatible backend.

The conformance harness (run_conformance.py) needs the *same* upstream reply
for every run and every implementation, so that any difference in the report
is a difference in the proxy under test rather than in the model. A real
backend cannot do that; this can.

Scenario selection is by marker, not by header: the proxy forwards none of the
client's headers upstream, and its request body is built from the buffer text.
So a case picks its scenario by embedding "@@SCENARIO:<name>@@" in the buffer
it sends, and this server reads the marker back out of the prompt.

GET /_last returns the most recent upstream request body this server received,
which is how the harness asserts on the *outgoing* payload shape (that no
"stop" field is sent, that reasoning_effort is top-level, and so on).
"""

import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_MARKER = re.compile(r'@@SCENARIO:([a-z0-9_]+)@@')

# A completion long enough to exercise both the 30-line and 8192-char caps.
_LONG_LINES = '\n'.join('  WRITELN(%d);' % i for i in range(80))
_LONG_CHARS = 'X' * 9000


def _chat(content, finish_reason='stop', extra_message=None):
    message = {'role': 'assistant', 'content': content}
    if extra_message:
        message.update(extra_message)
    return {
        'id':
        'stub-request-id',
        'model':
        'stub-model',
        'choices': [{
            'index': 0,
            'message': message,
            'finish_reason': finish_reason
        }],
    }


def scenario_response(name, payload):
    """Return (http_status, body_bytes_or_None, delay_seconds)."""
    if name == 'ok':
        return 200, _chat('  i := i + 1;'), 0
    if name == 'fenced':
        return 200, _chat('Here you go:\n```pascal\n  i := i + 1;\n```\n'), 0
    if name == 'echo':
        # Deliberately restates the tail of the probe buffer used by the
        # echo fixtures, to exercise strip_echo pass 1.
        return 200, _chat('FOR i := 1 TO 10 DO\n  WRITELN(i);'), 0
    if name == 'partial':
        return 200, _chat('DISPOSE(p2);'), 0
    if name == 'parts':
        return 200, _chat([{
            'type': 'text',
            'text': '  i := '
        }, {
            'type': 'text',
            'text': 'i + 1;'
        }]), 0
    if name == 'empty':
        return 200, _chat('   \n  \n'), 0
    if name == 'controls':
        return 200, _chat('  i := 1;\r\n\x00\x1b[31m  j := 2;\x7f'), 0
    if name == 'special_token':
        return 200, _chat('  i := 1;\n<|im_end|>  never reached'), 0
    if name == 'many_lines':
        return 200, _chat(_LONG_LINES), 0
    if name == 'many_chars':
        return 200, _chat(_LONG_CHARS), 0
    if name == 'no_choices':
        return 200, {'id': 'x', 'model': 'm', 'choices': []}, 0
    if name == 'not_an_object':
        return 200, [], 0
    if name == 'null_content':
        return 200, _chat(None), 0
    if name == 'reasoning_exhausted':
        return 200, _chat('',
                          finish_reason='length',
                          extra_message={'reasoning_content':
                                         'thinking...'}), 0
    if name == 'http_500':
        return 500, {'error': 'stub upstream failure'}, 0
    if name == 'malformed':
        return 'RAW', b'{not json at all', 0
    if name == 'slow':
        return 200, _chat('too late'), 30
    return 200, _chat('  i := i + 1;'), 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    calibrate_ok = None  # when set, only this effort value succeeds
    last_payload = None

    def log_message(self, fmt, *args):  # keep the harness output clean
        pass

    def _send(self, status, body_bytes):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_GET(self):
        if self.path != '/_last':
            self._send(404, b'{"error":"not found"}')
            return
        body = json.dumps(Handler.last_payload, sort_keys=True).encode('utf-8')
        self._send(200, body)

    def do_POST(self):
        length = int(self.headers.get('Content-Length') or '0')
        raw = self.rfile.read(length) if length > 0 else b''
        try:
            payload = json.loads(raw.decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            payload = None
        Handler.last_payload = payload

        if self.path.rstrip('/') != '/v1/chat/completions':
            self._send(404, b'{"error":"not found"}')
            return

        prompt = ''
        if isinstance(payload, dict):
            for message in payload.get('messages') or []:
                if isinstance(message, dict) and message.get('role') == 'user':
                    prompt = message.get('content') or ''

        # Calibration mode ignores the marker: it answers on the strength of
        # the reasoning_effort field alone, so the harness can pin down which
        # candidate the proxy settles on and in what order it tries them.
        if Handler.calibrate_ok is not None:
            effort = payload.get('reasoning_effort', '') if isinstance(
                payload, dict) else ''
            if effort == Handler.calibrate_ok:
                status, body, delay = 200, _chat('  i := i + 1;'), 0
            else:
                status, body, delay = scenario_response(
                    'reasoning_exhausted', payload)
        else:
            found = _MARKER.search(prompt)
            status, body, delay = scenario_response(
                found.group(1) if found else 'ok', payload)

        if delay:
            time.sleep(delay)
        if status == 'RAW':
            self._send(200, body)
            return
        self._send(status, json.dumps(body).encode('utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--calibrate-ok',
                        default=None,
                        help=('Answer successfully only when reasoning_effort '
                              'equals this value ("" for the omitted case); '
                              'every other value reports budget exhaustion.'))
    parser.add_argument(
        '--port-file',
        default='',
        help='Write the bound port number here once listening.')
    args = parser.parse_args()

    Handler.calibrate_ok = args.calibrate_ok
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    port = server.server_address[1]
    if args.port_file:
        with open(args.port_file, 'w', encoding='utf-8') as handle:
            handle.write(str(port))
    print('stub upstream listening on %s:%d' % (args.host, port),
          file=sys.stderr,
          flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
