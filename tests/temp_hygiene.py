#!/usr/bin/env python3
"""Temporary ownership, exit/signal cleanup, and parallel fixture regressions."""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import native_temp

BASE = Path('/tmp/native-pascal-1981')


class TemporaryHygiene(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='hygiene-')
        self.work = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def script(self, name, text):
        path = self.work / name
        path.write_text(text)
        path.chmod(0o700)
        return path

    def assert_removed(self, paths):
        for path in paths:
            path = Path(path)
            self.assertTrue(path.is_relative_to(BASE), path)
            self.assertFalse(path.exists(), path)
        self.assertTrue(BASE.is_dir())
        self.assertTrue(self.work.is_dir())  # unrelated active owner's data

    def test_shell_exits_and_signals(self):
        script = self.script(
            'shell.sh', f'''#!/usr/bin/env bash
source "{ROOT}/scripts/temp-env.sh"
echo "$TMPDIR"
touch "$TMPDIR/data"
trap ':' EXIT  # replacing the child's EXIT trap must not leak the workspace
if [[ $1 == hold ]]; then read -r answer; exit 0; fi
exit "$1"
''')
        for code in (0, 7):
            result = subprocess.run(
                ['bash', str(script), str(code)],
                capture_output=True,
                text=True,
                timeout=15)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assert_removed([result.stdout.strip()])
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with subprocess.Popen(['bash', str(script), 'hold'],
                                  stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  text=True) as process:
                workspace = process.stdout.readline().strip()
                self.assertTrue(Path(workspace).is_dir())
                process.send_signal(sig)
                _, err = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 128 + sig, err)
                self.assert_removed([workspace])

    def test_python_exits_and_signals(self):
        script = self.script(
            'python.py', f'''import os, signal, sys, tempfile
sys.path.insert(0, {str(ROOT / 'scripts')!r})
import native_temp
print(native_temp.WORK, flush=True)
tempfile.mkstemp()
if sys.argv[1] == 'hold':
    sys.stdin.readline()
else:
    sys.exit(int(sys.argv[1]))
''')
        for code in (0, 7):
            result = subprocess.run(
                [sys.executable, str(script),
                 str(code)],
                capture_output=True,
                text=True,
                timeout=15)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assert_removed([result.stdout.strip()])
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with subprocess.Popen(
                [sys.executable, str(script), 'hold'],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True) as process:
                workspace = process.stdout.readline().strip()
                process.send_signal(sig)
                process.communicate(timeout=15)
                self.assertNotEqual(process.returncode, 0)
                self.assert_removed([workspace])

    def test_parallel_owner_survives(self):
        script = self.script(
            'active.sh', f'''#!/usr/bin/env bash
source "{ROOT}/scripts/temp-env.sh"
touch "$TMPDIR/keep"
echo "$TMPDIR"
read -r answer
''')
        with subprocess.Popen(['bash', str(script)],
                              stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE,
                              text=True) as active:
            workspace = Path(active.stdout.readline().strip())
            result = subprocess.run(['bash', str(script)],
                                    input='done\n',
                                    capture_output=True,
                                    text=True,
                                    timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotEqual(str(workspace), result.stdout.strip())
            self.assert_removed([result.stdout.strip()])
            self.assertTrue((workspace / 'keep').is_file())
            active.communicate('done\n', timeout=15)
            self.assert_removed([workspace])

    def test_runtime_owner_and_signals(self):
        source = self.script(
            'runtime.c', r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
extern char *pas_driver_temp_file(const char *suffix);
int main(int argc, char **argv) {
    char *path = pas_driver_temp_file(".ll");
    if (!path) return 2;
    puts(path); fflush(stdout);
    if (!strcmp(argv[1], "fork")) {
        int status;
        pid_t pid = fork();
        if (!pid) exit(0);
        waitpid(pid, &status, 0);
        return access(path, F_OK) == 0 ? 0 : 3;
    }
    if (!strcmp(argv[1], "hold")) { getchar(); return 0; }
    return atoi(argv[1]);
}
''')
        exe = self.work / 'runtime'
        subprocess.run([
            os.environ.get('CC', 'clang'), '-Wall', '-Wextra',
            str(source),
            str(ROOT / 'runtime/temporary.c'), '-o',
            str(exe)
        ],
                       check=True,
                       capture_output=True,
                       text=True)
        for mode, code in [('0', 0), ('7', 7), ('fork', 0)]:
            result = subprocess.run([str(exe), mode],
                                    capture_output=True,
                                    text=True,
                                    timeout=15)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assert_removed([Path(result.stdout.strip()).parent])
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            with subprocess.Popen([str(exe), 'hold'],
                                  stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  text=True) as process:
                path = Path(process.stdout.readline().strip())
                self.assertTrue(path.is_file())
                process.send_signal(sig)
                process.communicate(timeout=15)
                self.assertEqual(process.returncode, 128 + sig)
                self.assert_removed([path.parent])

    def test_anonymous_file_storage(self):
        source = self.script(
            'anonymous.c', r'''
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
extern FILE *pas_project_tmpfile(void);
int main(int argc, char **argv) {
    FILE *stream = pas_project_tmpfile();
    char fdpath[64], path[512];
    ssize_t length;
    if (!stream) return 2;
    snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", fileno(stream));
    length = readlink(fdpath, path, sizeof(path) - 1);
    if (length < 0) return 3;
    path[length] = 0;
    puts(path); fflush(stdout);
    fputs("hello", stream); rewind(stream);
    if (fgetc(stream) != 'h') return 4;
    if (atoi(argv[1])) raise(SIGTERM);
    return fclose(stream);
}
''')
        exe = self.work / 'anonymous'
        subprocess.run([
            os.environ.get('CC', 'clang'),
            str(source),
            str(ROOT / 'runtime/temporary.c'), '-o',
            str(exe)
        ],
                       check=True,
                       capture_output=True,
                       text=True)
        for mode, code in [('0', 0), ('1', -signal.SIGTERM)]:
            result = subprocess.run([str(exe), mode],
                                    capture_output=True,
                                    text=True,
                                    timeout=15)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertTrue(result.stdout.strip().endswith(' (deleted)'))
            path = Path(result.stdout.strip().removesuffix(' (deleted)'))
            self.assert_removed([path.parent])

    def test_driver_multifile_cleanup(self):
        # Replace only clang: the real four-stage pipeline must still run.
        cc = self.script(
            'cc', f'''#!{sys.executable}
import json, os, signal, sys
from pathlib import Path
ir = next(Path(arg) for arg in sys.argv[1:] if arg.endswith('.ll'))
print(json.dumps([str(p) for p in ir.parent.iterdir()]), flush=True)
mode = os.environ['HYGIENE_MODE']
if mode == 'signal':
    os.kill(os.getppid(), signal.SIGTERM)
sys.exit(7 if mode == 'failure' else 0)
''')
        source = ROOT / 'tests/golden/01_hello.pas'
        for mode, code in [('success', 0), ('failure', 7), ('signal', 143)]:
            env = dict(os.environ, PASCAL1981_CC=str(cc), HYGIENE_MODE=mode)
            result = subprocess.run([
                str(ROOT / 'bin/pascal1981'),
                str(source),
                str(source), '-o',
                str(self.work / 'program')
            ],
                                    env=env,
                                    capture_output=True,
                                    text=True,
                                    timeout=30)
            self.assertEqual(result.returncode, code, result.stderr)
            reports = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertTrue(reports)
            paths = [Path(path) for report in reports for path in report]
            self.assertGreaterEqual(len(paths),
                                    3)  # primary IR, secondary IR/object
            self.assertEqual(len({path.parent for path in paths}), 1)
            self.assert_removed([paths[0].parent])

    def test_driver_pipeline_failure_cleanup(self):
        report = self.work / 'report'
        stage = self.script(
            'bad-codegen', f'''#!{sys.executable}
import os, sys
from pathlib import Path
Path({str(report)!r}).write_text(os.readlink('/proc/self/fd/1'))
sys.stdin.read()
sys.exit(7)
''')
        result = subprocess.run([
            str(ROOT / 'bin/pascal1981'),
            str(ROOT / 'tests/golden/01_hello.pas'), '-o',
            str(self.work / 'program')
        ],
                                env=dict(os.environ,
                                         PASCAL1981_CODEGEN=str(stage)),
                                capture_output=True,
                                text=True,
                                timeout=30)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assert_removed([Path(report.read_text().strip()).parent])

    def test_unsafe_root_rejected(self):
        # Each case runs in a bubblewrap sandbox with a private /tmp, so the
        # shared namespace is never made unsafe for concurrent owners.
        # scripts/test-env.sh preloads the no-core shim, whose
        # PR_SET_DUMPABLE=0 stops bwrap writing its uid map; these sandboxed
        # programs never abort, so drop only that preload entry.
        env = {k: v for k, v in os.environ.items() if k != 'TMPDIR'}
        preload = [
            entry for entry in env.pop('LD_PRELOAD', '').split(':')
            if entry and not entry.endswith('/test-no-core.so')
        ]
        if preload:
            env['LD_PRELOAD'] = ':'.join(preload)
        if subprocess.run(['bwrap', '--ro-bind', '/', '/', 'true'],
                          env=env,
                          capture_output=True).returncode != 0:
            self.skipTest('bwrap sandbox unavailable')
        source = self.script(
            'root.c', r'''
#include <stdio.h>
#include <string.h>
extern char *pas_driver_temp_file(const char *suffix);
extern FILE *pas_project_tmpfile(void);
extern int pas_sys_temp_dir(const char *prefix, char *out, int outcap);
int main(int argc, char **argv) {
    char out[256];
    if (argc != 2) return 9;
    if (!strcmp(argv[1], "driver")) return pas_driver_temp_file(".ll") ? 0 : 2;
    if (!strcmp(argv[1], "file")) return pas_project_tmpfile() ? 0 : 2;
    return pas_sys_temp_dir("probe", out, sizeof(out)) == 0 ? 0 : 2;
}
''')
        subprocess.run([
            os.environ.get('CC', 'clang'), '-Wall', '-Wextra', '-I',
            str(ROOT / 'runtime'),
            str(source),
            str(ROOT / 'runtime/temporary.c'),
            str(ROOT / 'runtime/sysutil.c'), '-o',
            str(self.work / 'root')
        ],
                       check=True,
                       capture_output=True,
                       text=True)
        shell = self.script('root.sh',
                            f'source "{ROOT}/scripts/temp-env.sh"\ntrue\n')
        users = {
            'driver': ['/tmp/work/root', 'driver'],
            'file': ['/tmp/work/root', 'file'],
            'SysTempDirCreate': ['/tmp/work/root', 'sysdir'],
            'python': [
                sys.executable, '-c',
                f'import sys; sys.path.insert(0, {str(ROOT / "scripts")!r}); '
                'import native_temp'
            ],
            'shell': ['bash', f'/tmp/work/{shell.name}'],
        }
        emacs = shutil.which('emacs')
        if emacs:
            users['emacs'] = [
                emacs, '--batch', '-Q', '-l',
                str(ROOT / 'elisp/pascal1981-mode.el'), '--eval',
                '(pascal1981--make-temp-directory)'
            ]
        root = str(BASE)
        cases = {
            'absent': ([], 'umask 002', True),  # created private anyway
            'private': ([], f'mkdir -m 700 {root}', True),
            'symlink':
            ([], f'mkdir -m 700 /tmp/real && ln -s /tmp/real {root}', False),
            'group-writable': ([], f'mkdir {root} && chmod 730 {root}', False),
            'other-writable': ([], f'mkdir {root} && chmod 703 {root}', False),
            'foreign-owner': (['--ro-bind', '/usr', root], ':', False),
            'regular-file': ([], f'touch {root}', False),
        }
        for case, (mounts, setup, safe) in cases.items():
            for user, command in users.items():
                with self.subTest(case=case, user=user):
                    result = subprocess.run(
                        [
                            'bwrap', '--ro-bind', '/', '/', '--dev', '/dev',
                            '--proc', '/proc', '--tmpfs', '/tmp', '--ro-bind',
                            str(self.work), '/tmp/work'
                        ] + mounts +
                        ['bash', '-c', f'{setup} && exec "$@"', 'setup'] +
                        command,
                        env=env,
                        capture_output=True,
                        text=True,
                        timeout=30)
                    if safe:
                        self.assertEqual(result.returncode, 0, result.stderr)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        if user in ('python', 'shell', 'emacs'
                                    ) and case not in ('regular-file', ):
                            self.assertIn('nsafe temporary root',
                                          result.stderr)

    def test_parallel_fixture_cells(self):
        fixture = 'tests/dialect/vintage_enum_io.pas'
        result = subprocess.run(['bash', 'tests/run.sh', '-j', '8'] +
                                [fixture] * 16,
                                cwd=ROOT,
                                capture_output=True,
                                text=True,
                                timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('16 passed, 0 failed (total 16)', result.stdout)

    def test_proxy_stub_port_publication(self):
        with mock.patch.object(sys, 'path',
                               [str(ROOT / 'tests/proxy'), *sys.path]):
            import run_conformance as conformance

        harness = conformance.Harness([])
        publications = []
        try:
            for mode in ('success', 'success', 'spawn-error', 'early-exit',
                         'empty', 'malformed', 'unready', 'timeout'):
                with self.subTest(mode=mode):

                    def spawn(argv, **kwargs):
                        path = Path(argv[argv.index('--port-file') + 1])
                        self.assertTrue(path.is_relative_to(harness._log_dir))
                        self.assertTrue(path.is_relative_to(native_temp.WORK))
                        self.assertEqual(path.parent.stat().st_mode & 0o777,
                                         0o700)
                        publications.append(path)
                        if mode == 'spawn-error':
                            raise OSError('injected spawn failure')
                        if mode != 'early-exit':
                            path.write_text('' if mode ==
                                            'empty' else 'invalid' if mode ==
                                            'malformed' else '12345')
                        return mock.Mock(poll=mock.Mock(return_value=1))

                    clock = mock.Mock(time=mock.Mock(side_effect=[0, 21]))
                    with mock.patch.object(conformance, 'HERE', str(self.work)), \
                            mock.patch.object(conformance.subprocess, 'Popen',
                                              side_effect=spawn), \
                            mock.patch.object(conformance, 'wait_for_port',
                                              return_value=mode == 'success'), \
                            mock.patch.object(conformance, 'time',
                                              clock if mode == 'timeout'
                                              else conformance.time):
                        if mode == 'success':
                            self.assertEqual(harness.start_stub(), 12345)
                        else:
                            error = (OSError
                                     if mode == 'spawn-error' else ValueError
                                     if mode == 'malformed' else RuntimeError)
                            with self.assertRaises(error):
                                harness.start_stub()
                    self.assertFalse(publications[-1].parent.exists())
                    # No parent directory remains for a late child to publish.
                    with self.assertRaises(FileNotFoundError):
                        publications[-1].write_text('12345')
                    self.assertTrue(Path(harness._log_dir).is_dir())
                    self.assertTrue(self.work.is_dir())
            self.assertEqual(len(set(publications)), 8)
        finally:
            harness.stop_all()

        # Real listeners: repeated startup in one harness, then concurrent
        # harnesses in this same PID (the former source-path key would collide).
        harnesses = [conformance.Harness([]), conformance.Harness([])]
        try:
            for _ in range(2):
                self.assertGreater(harnesses[0].start_stub(), 0)
                harnesses[0].stop_all()
            with ThreadPoolExecutor(max_workers=2) as pool:
                ports = list(pool.map(lambda h: h.start_stub(), harnesses))
            self.assertEqual(len(set(ports)), 2)
            for owner in harnesses:
                self.assertFalse([
                    path for path in Path(owner._log_dir).glob('stub-*')
                    if path.is_dir()
                ])
                self.assertTrue(
                    Path(owner._log_dir).is_relative_to(native_temp.WORK))
        finally:
            for owner in harnesses:
                owner.stop_all()

    def test_migration_audit(self):
        for directory in ('tests', 'scripts', 'bootstrap/tests'):
            for path in (ROOT / directory).rglob('*.sh'):
                if path.name == 'temp-env.sh':
                    continue
                if 'mktemp' in path.read_text():
                    self.assertIn('temp-env.sh', path.read_text(), path)
        for path in (ROOT / 'tests').rglob('*.py'):
            if 'import tempfile' in path.read_text():
                self.assertIn('import native_temp', path.read_text(), path)
        for path in (ROOT / 'tests').rglob('*.pas'):
            self.assertNotIn("'/tmp/", path.read_text(), path)


if __name__ == '__main__':
    unittest.main()
