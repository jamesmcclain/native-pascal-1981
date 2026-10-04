#!/usr/bin/env python3
"""Bounded checks for the test-only crash-reporter suppression launcher."""
import os
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = ROOT / 'scripts/test-env.sh'


def main():
    if not sys.platform.startswith('linux'):
        print('SKIP: Linux dumpability checks')
        return
    environment = os.environ.copy()
    # Test the launcher itself, independent of an enclosing test environment.
    environment.pop('LD_PRELOAD', None)
    environment.pop('PASCAL_TEST_CORES', None)
    check = 'import ctypes; assert ctypes.CDLL(None).prctl(3, 0, 0, 0, 0) == 0'
    failure = check + "; import os; os.write(1, b'prefix\\n'); os.write(2, b'expected failure\\n'); os.abort()"
    # Descendant exec must reapply the constructor, not just inherit the
    # launcher's dumpability (Linux resets it during exec).
    parent = (
        'import subprocess, sys; '
        f'p = subprocess.run([sys.executable, "-c", {failure!r}], capture_output=True, timeout=3); '
        'assert p.returncode == -6, p; '
        'assert p.stdout == b"prefix\\n", p; '
        'assert p.stderr == b"expected failure\\n", p')
    for code in [check, parent]:
        result = subprocess.run([str(LAUNCHER), sys.executable, '-c', code],
                                cwd=ROOT,
                                env=environment,
                                capture_output=True,
                                timeout=5)
        assert result.returncode == 0, result
        assert not result.stdout and not result.stderr, result
    # Direct failing command retains its signal too (launcher uses exec).
    result = subprocess.run([str(LAUNCHER), sys.executable, '-c', failure],
                            cwd=ROOT,
                            env=environment,
                            capture_output=True,
                            timeout=5)
    assert result.returncode == -signal.SIGABRT, result
    assert result.stdout == b'prefix\n' and result.stderr == b'expected failure\n', result
    environment['PASCAL_TEST_CORES'] = '1'
    result = subprocess.run([
        str(LAUNCHER), sys.executable, '-c',
        'import ctypes; assert ctypes.CDLL(None).prctl(3, 0, 0, 0, 0) == 1'
    ],
                            cwd=ROOT,
                            env=environment,
                            capture_output=True,
                            timeout=5)
    assert result.returncode == 0, result
    # The destructive clean-bootstrap regression must not race other goals.
    result = subprocess.run(['make', '-n', 'test-bootstrap', 'test-native'],
                            cwd=ROOT,
                            capture_output=True,
                            timeout=5)
    assert result.returncode != 0, result
    assert b'run it separately from other goals' in result.stderr, result
    print(
        'PASS: test-only no-core launcher, descendant exec, SIGABRT/diagnostics, opt-out; destructive-goal guard'
    )


if __name__ == '__main__':
    main()
