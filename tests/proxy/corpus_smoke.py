#!/usr/bin/env python3
"""Replay a corpus of realistic /complete requests through the proxy.

The conformance suite (run.sh) answers "does this implementation behave
exactly like the one it replaces". It cannot answer "does it work" -- its
backend is a stub that returns the same canned reply to every request, its
buffers are a few lines long, and its buffer limit is 1024 characters. A proxy
could pass all 47 cases and still fall over on a real 4 KB buffer or return
nothing usable from a real model.

This fills that gap. It replays 64 corpus items -- 56 cut from real,
known-compiling programs in tests/golden and tests/integration at a clean line
boundary, plus 8 hand-written micro-cases and whole-task prompts -- and reports
what came back. Buffers run from empty to 3875 characters.

Against a live backend it also does the check that makes the corpus worth
keeping: append the completion to the buffer, compile it with the real
compiler, and count how many actually build. That is an objective quality
signal, not a protocol check, and no stub can produce it.

    tests/proxy/corpus_smoke.py                      # against the stub
    tests/proxy/corpus_smoke.py --base-url URL       # against a real backend
    tests/proxy/corpus_smoke.py --limit 10           # a quick pass

Exit status is 0 unless a request failed at the protocol level -- a wrong
status, a malformed body, a connection that died. Completion *quality* is
reported, never asserted: a live model returns different text every run, so
there is nothing here to pin.
"""

import argparse
import json
import pathlib
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
CORPUS = HERE / 'corpus'


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def wait_for_port(port, timeout, proc):
    """Wait for a TCP listener, not for GET /health -- that endpoint calls
    the real backend on every request, so polling it generates real load and
    can queue up ahead of the requests this is about to make."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(('127.0.0.1', port), 0.25):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def load_corpus(limit):
    items = [
        json.loads(path.read_text(encoding='utf-8'))
        for path in sorted(CORPUS.glob('*.json'))
    ]
    return items[:limit] if limit else items


def complete(port, item, timeout):
    """POST one corpus item. Returns (status, body_or_error_string)."""
    payload = json.dumps({
        'goal': item.get('goal', ''),
        'buffer': item['buffer'],
        'cursor': item['cursor'],
    }).encode('utf-8')
    request = urllib.request.Request(
        'http://127.0.0.1:%d/complete' % port,
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST')
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode('utf-8', 'replace')
    except Exception as exc:  # noqa: BLE001 -- any transport failure counts
        return None, str(exc)


def compiles(compiler, buffer_text, completion):
    """Does buffer + completion build with the real compiler?"""
    with tempfile.TemporaryDirectory() as work:
        source = pathlib.Path(work) / 'candidate.pas'
        source.write_text(buffer_text + completion, encoding='utf-8')
        try:
            proc = subprocess.run([str(compiler), str(source)],
                                  cwd=work,
                                  capture_output=True,
                                  text=True,
                                  timeout=30)
        except subprocess.TimeoutExpired:
            return False, 'compiler timed out'
        if proc.returncode == 0:
            return True, ''
        return False, (proc.stderr or proc.stdout or '').strip()[-200:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--proxy-bin',
                        default=str(REPO / 'bin' / 'pascal1981-proxy'),
                        help='proxy to exercise (default: the Pascal port)')
    parser.add_argument('--base-url',
                        default='',
                        help='live backend; omit to start the local stub')
    parser.add_argument('--limit', type=int, default=0)
    parser.add_argument('--timeout', type=float, default=60.0)
    parser.add_argument('--max-tokens', default='512')
    parser.add_argument('--llm-model', default='stub-model')
    parser.add_argument('--no-compile-check', action='store_true')
    parser.add_argument('-v', '--verbose', action='store_true')
    args = parser.parse_args()

    items = load_corpus(args.limit)

    procs = []
    try:
        base_url = args.base_url
        live = bool(base_url)
        if not live:
            # The stub answers every item with the same canned completion, so
            # only the request path is under test here: realistic buffer
            # sizes, cursor positions and goals reaching the proxy intact.
            stub_port = free_port()
            stub = subprocess.Popen([
                sys.executable,
                str(HERE / 'stub_upstream.py'), '--port',
                str(stub_port)
            ],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
            procs.append(stub)
            if not wait_for_port(stub_port, 10, stub):
                print('stub upstream did not start', file=sys.stderr)
                return 1
            base_url = 'http://127.0.0.1:%d/v1' % stub_port

        port = free_port()
        argv = shlex.split(args.proxy_bin) + [
            '--host',
            '127.0.0.1',
            '--port',
            str(port),
            '--llm-base-url',
            base_url,
            '--llm-model',
            args.llm_model,
            '--max-tokens',
            args.max_tokens,
            '--upstream-timeout',
            str(int(args.timeout)),
            '--reasoning-effort',
            'none' if not live else 'auto',
        ]
        if args.verbose:
            print('+ %s' % ' '.join(shlex.quote(a) for a in argv),
                  file=sys.stderr)
        proxy = subprocess.Popen(
            argv,
            stdout=subprocess.DEVNULL,
            stderr=None if args.verbose else subprocess.DEVNULL)
        procs.append(proxy)
        # Calibration makes several upstream calls before the socket opens.
        if not wait_for_port(port, 120, proxy):
            print('proxy failed to start on port %d' % port, file=sys.stderr)
            return 1

        compiler = REPO / 'bin' / 'pascal1981'
        check_compiles = live and not args.no_compile_check and compiler.exists(
        )

        failures = 0
        empty = 0
        built = 0
        eligible = 0
        for item in items:
            status, body = complete(port, item, args.timeout)
            if status != 200 or not isinstance(body, dict) \
                    or 'completions' not in body:
                failures += 1
                print('FAIL %-32s status=%s %s' %
                      (item['id'], status, str(body)[:120]))
                continue
            completions = body['completions']
            if not completions:
                empty += 1
                print('EMPTY %-31s (no completion returned)' % item['id'])
                continue
            text = completions[0]
            note = '%d chars' % len(text)
            if check_compiles and item.get('compiles_when_appended'):
                eligible += 1
                ok, diagnostic = compiles(compiler, item['buffer'], text)
                if ok:
                    built += 1
                    note += ', compiles'
                else:
                    note += ', does not compile'
                    if args.verbose and diagnostic:
                        note += ': ' + diagnostic
            print('ok   %-32s %s' % (item['id'], note))

        print()
        print('%d items: %d protocol failures, %d empty completions' %
              (len(items), failures, empty))
        if eligible:
            print('%d of %d completions compiled when appended' %
                  (built, eligible))
        elif live:
            print('compile check skipped (bin/pascal1981 not built)')
        else:
            print('compile check skipped: the stub returns one canned reply '
                  'to every request, so it would measure nothing')
        return 1 if failures else 0
    finally:
        for proc in reversed(procs):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()


if __name__ == '__main__':
    sys.exit(main())
