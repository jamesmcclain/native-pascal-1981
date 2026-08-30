#!/usr/bin/env python3
"""Drive one proxy implementation through the conformance corpus.

Usage:
    run_conformance.py --proxy-bin bin/pascal1981-proxy --out reports/pascal.json
    run_conformance.py --compare golden.json reports/pascal.json

The point is differential testing: any implementation is pointed at the same
deterministic stub backend, driven with the same raw bytes, and its report
compared against the recorded one. Any difference is a difference in the
proxy, because nothing else in the loop varies. golden.json was recorded from
the Python implementation this port replaced.

The runner -- not the caller -- owns the flags the implementation is started
with, so both implementations are configured identically by construction and
a mismatch can never be an artefact of how they were invoked.
"""

import argparse
import json
import os
import shlex
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# Small on purpose: it keeps the size-limit cases cheap (a 4KB body instead of
# a 128KB one) without changing any behaviour under test.
BUFFER_LIMIT = 1024
UPSTREAM_TIMEOUT = 3
MAX_LINES = 30
READ_TIMEOUT = 30


def wait_for_port(host, port, timeout=30.0, proc=None):
    """Wait for a TCP listener, deliberately not for GET /health.

    /health is a live probe: it calls the real backend on every request. A
    poll loop against it was observed to generate genuine backend load --
    each attempt's short timeout abandoned the connection, but a backend
    serving one connection at a time kept working the abandoned request
    anyway, piling up ahead of the harness's real requests. Opening a socket
    answers the only question being asked here, which is whether the process
    is up, and costs the backend nothing.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            return False
        try:
            with socket.create_connection((host, port), 0.5):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def send_raw(host, port, request_bytes, read_timeout=READ_TIMEOUT):
    """Send raw bytes, half-close, and read the whole reply until EOF."""
    with socket.create_connection((host, port), read_timeout) as sock:
        sock.settimeout(read_timeout)
        sock.sendall(request_bytes)
        try:
            sock.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        chunks = []
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                chunks.append(b'<<READ TIMED OUT>>')
                break
            if not chunk:
                break
            chunks.append(chunk)
        return b''.join(chunks)


def parse_response(raw, upstream_url):
    """Reduce a raw HTTP response to the parts that are part of the contract.

    Deliberately dropped: Server and Date headers, the HTTP version, and the
    reason phrase -- all of them are free for an implementation to choose and
    none is anything a client depends on.
    """
    if not raw:
        return {'status': None, 'error': 'no response'}
    head, _, body = raw.partition(b'\r\n\r\n')
    lines = head.decode('latin-1').split('\r\n')
    status_line = lines[0] if lines else ''
    parts = status_line.split(None, 2)
    status = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None

    content_type = None
    for line in lines[1:]:
        name, _, value = line.partition(':')
        if name.strip().lower() == 'content-type':
            content_type = value.strip()

    result = {'status': status, 'content_type': content_type}
    try:
        decoded = body.decode('utf-8')
    except UnicodeDecodeError:
        result['body_raw'] = repr(body)
        return result
    try:
        parsed = json.loads(decoded)
    except ValueError:
        result['body_raw'] = decoded
        return result
    result['body'] = normalize(parsed, upstream_url)
    return result


def normalize(value, upstream_url):
    """Mask the one genuinely non-deterministic value: the stub's port."""
    if isinstance(value, dict):
        return {k: normalize(v, upstream_url) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v, upstream_url) for v in value]
    if isinstance(value, str) and upstream_url and upstream_url in value:
        return value.replace(upstream_url, '<UPSTREAM>')
    return value


class Harness:

    def __init__(self, proxy_argv, verbose=False, native_runner='', golden=''):
        self.proxy_argv = proxy_argv
        self.verbose = verbose
        self.native_runner = native_runner
        self.golden = golden
        self.procs = []
        # Child stderr goes to a file, never to a PIPE. A PIPE has to be
        # actively drained or the child blocks once the ~64KB buffer fills,
        # and nothing here drains one -- the read below happens only after
        # the child is already dead. It is a latent hang rather than a live
        # one today, because neither implementation logs per request, but
        # the Pascal proxy forks per connection and every child inherits
        # this same descriptor, so it is one WRITELN away from mattering.
        # A file gets the diagnostics without anything to drain.
        self._log_dir = tempfile.mkdtemp(prefix='proxy-conformance-')
        self._logs = {}

    def _log_for(self, name):
        path = os.path.join(self._log_dir,
                            '%s-%d.log' % (name, len(self._logs)))
        handle = open(path, 'w+b')
        self._logs[handle] = path
        return handle

    def _read_log(self, handle):
        handle.flush()
        with open(self._logs[handle], 'rb') as saved:
            return saved.read()

    def start_stub(self, calibrate_ok=None):
        port_file = os.path.join(HERE, '.stub-port-%d' % os.getpid())
        if os.path.exists(port_file):
            os.unlink(port_file)
        argv = [
            sys.executable,
            os.path.join(HERE, 'stub_upstream.py'), '--port', '0',
            '--port-file', port_file
        ]
        if calibrate_ok is not None:
            argv += ['--calibrate-ok', calibrate_ok]
        log = self._log_for('stub')
        proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=log)
        self.procs.append(proc)
        deadline = time.time() + 20
        while time.time() < deadline:
            if os.path.exists(port_file):
                text = open(port_file, encoding='utf-8').read().strip()
                if text:
                    port = int(text)
                    os.unlink(port_file)
                    if wait_for_port('127.0.0.1', port, 10, proc):
                        return port
                    break
            if proc.poll() is not None:
                break
            time.sleep(0.05)
        raise RuntimeError('stub upstream failed to start')

    def start_proxy(self, upstream_url, reasoning_effort='none'):
        port = free_port()
        argv = list(self.proxy_argv) + [
            '--host',
            '127.0.0.1',
            '--port',
            str(port),
            '--llm-base-url',
            upstream_url,
            '--llm-model',
            'stub-model',
            '--buffer-limit',
            str(BUFFER_LIMIT),
            '--upstream-timeout',
            str(UPSTREAM_TIMEOUT),
            '--max-lines',
            str(MAX_LINES),
            '--temperature',
            '0.0',
            '--max-tokens',
            '512',
            '--reasoning-effort',
            reasoning_effort,
        ]
        if self.verbose:
            print('+ %s' % ' '.join(shlex.quote(a) for a in argv),
                  file=sys.stderr)
        log = self._log_for('proxy')
        proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=log)
        self.procs.append(proc)
        # Calibration makes several upstream calls before the socket opens.
        if not wait_for_port('127.0.0.1', port, 60, proc):
            err = self._read_log(log)
            raise RuntimeError(
                'proxy failed to start on port %d%s' %
                (port, (': ' + err.decode('utf-8', 'replace')) if err else ''))
        return port

    def stop_all(self):
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
        self.procs = []
        for handle in self._logs:
            handle.close()
        self._logs = {}


def run_corpus(harness):
    stub_port = harness.start_stub()
    upstream_url = 'http://127.0.0.1:%d/v1' % stub_port
    proxy_port = harness.start_proxy(upstream_url)
    if harness.native_runner:
        argv = [
            harness.native_runner, '--host', '127.0.0.1', '--port',
            str(proxy_port), '--stub-port',
            str(stub_port), '--upstream-url', upstream_url, '--fixtures',
            os.path.join(HERE, 'conformance_cases.json')
        ]
        if harness.golden:
            argv += ['--golden', harness.golden]
        result = subprocess.run(argv,
                                capture_output=True,
                                text=True,
                                check=False)
        if result.returncode:
            raise RuntimeError('native conformance runner failed: %s' %
                               result.stderr)
        return json.loads(result.stdout)['cases']
    raise RuntimeError('native conformance runner is required')


def run_health_unreachable(harness):
    """Run the native dead-upstream /health assertion."""
    dead_port = free_port()
    upstream_url = 'http://127.0.0.1:%d/v1' % dead_port
    proxy_port = harness.start_proxy(upstream_url)
    result = subprocess.run([
        harness.native_runner, '--host', '127.0.0.1', '--port',
        str(proxy_port), '--upstream-url', upstream_url, '--health-unreachable'
    ],
                            capture_output=True,
                            text=True,
                            check=False)
    if result.returncode:
        raise RuntimeError('native health runner failed: %s' % result.stderr)
    return json.loads(result.stdout)['cases']


def run_calibration(harness):
    """Pin which reasoning_effort --reasoning-effort auto settles on."""
    entries = []
    for expected in ['none', 'medium', '']:
        stub_port = harness.start_stub(calibrate_ok=expected)
        upstream_url = 'http://127.0.0.1:%d/v1' % stub_port
        proxy_port = harness.start_proxy(upstream_url, reasoning_effort='auto')
        raw = send_raw(
            '127.0.0.1', proxy_port, b'GET /health HTTP/1.1\r\nHost: x\r\n'
            b'Connection: close\r\n\r\n')
        record = parse_response(raw, upstream_url)
        record['name'] = 'calibrate_settles_on_%s' % (expected or 'omitted')
        record['note'] = (
            'Only reasoning_effort=%r answers; every other candidate reports '
            'budget exhaustion. The proxy must try none, low, medium, high, '
            'omitted in that order and settle on the one that works.' %
            expected)
        entries.append(record)
    return entries


def build_report(proxy_argv, verbose, native_runner='', golden=''):
    harness = Harness(proxy_argv, verbose, native_runner, golden)
    entries = []
    try:
        entries += run_corpus(harness)
        harness.stop_all()
        entries += run_health_unreachable(harness)
        harness.stop_all()
        entries += run_calibration(harness)
    finally:
        harness.stop_all()
    return {'cases': entries}


def compare(left_path, right_path):
    left = json.load(open(left_path, encoding='utf-8'))['cases']
    right = json.load(open(right_path, encoding='utf-8'))['cases']
    left_by = {entry['name']: entry for entry in left}
    right_by = {entry['name']: entry for entry in right}

    def strip(entry):
        return {k: v for k, v in entry.items() if k != 'note'}

    failures = []
    for name in sorted(set(left_by) | set(right_by)):
        if name not in left_by:
            failures.append('%s: missing from %s' % (name, left_path))
            continue
        if name not in right_by:
            failures.append('%s: missing from %s' % (name, right_path))
            continue
        want = strip(left_by[name])
        got = strip(right_by[name])
        if want != got:
            failures.append('%s:\n  expected: %s\n  actual:   %s' %
                            (name, json.dumps(want, sort_keys=True),
                             json.dumps(got, sort_keys=True)))
    if failures:
        print('%d of %d cases differ:\n' % (len(failures), len(left_by)))
        for line in failures:
            print(line)
        return 1
    print('all %d cases identical' % len(left_by))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proxy-bin',
                        help='Command that starts the proxy under test; the '
                        'runner appends the flags itself.')
    parser.add_argument('--out', default='', help='Write the report here.')
    parser.add_argument('--compare',
                        nargs=2,
                        metavar=('EXPECTED', 'ACTUAL'),
                        help='Compare two existing reports and exit nonzero '
                        'on any difference.')
    parser.add_argument('--native-runner',
                        help='Pascal fixture replay executable')
    parser.add_argument('--golden',
                        help='Golden report for native case checks')
    parser.add_argument('-v', '--verbose', action='store_true')
    args = parser.parse_args()

    if args.compare:
        return compare(*args.compare)
    if not args.proxy_bin:
        parser.error('--proxy-bin is required unless --compare is used')
    if not args.native_runner:
        parser.error('--native-runner is required when running the corpus')

    report = build_report(shlex.split(args.proxy_bin), args.verbose,
                          args.native_runner or '', args.golden or '')
    text = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, 'w', encoding='utf-8') as handle:
            handle.write(text)
        print('wrote %s (%d cases)' % (args.out, len(report['cases'])))
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
