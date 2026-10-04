#!/usr/bin/env python3
"""Executable gap inventory, not a claim that MATHCK is implemented."""
import json
import re
import resource
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / 'tests'
KINDS = {
    'known-gap-output',
    'known-gap-crash',
    'known-gap-compile-only',
    'known-gap-timeout',
    'known-gap-reject',
    'correct-reject',
    'correct-output',
    'out-of-scope-output',
    'correct-runtime-error',
}


def run(command, *, stdin='', timeout=30):
    return subprocess.run(command,
                          cwd=ROOT,
                          input=stdin,
                          text=True,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,
                          timeout=timeout)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def check(probe, dialect, opt, work):
    exe = work / 'probe'
    kind = probe['kind']
    require(kind in KINDS, f'unknown classification: {kind}')
    command = [
        str(ROOT / 'bin/pascal1981'), '--dialect', dialect, f'-O{opt}',
        str(TESTS / probe['fixture']), '-o',
        str(exe)
    ]
    # Known-gap compile-only probes are never executed here (none remain:
    # G9 is rejected at compile time, G26 fails with a conversion error).
    # G6-G8 now have defined arithmetic safety oracles.
    if kind == 'known-gap-compile-only':
        command.insert(1, '-c')
    compiled = run(command)
    if kind in {'known-gap-reject', 'correct-reject'}:
        require(
            compiled.returncode != 0,
            'unexpected compile acceptance; flip the gap expectation when fixed'
        )
        require(probe['diagnostic'] in compiled.stderr,
                f'wrong rejection diagnostic: {compiled.stderr!r}')
        return
    require(compiled.returncode == 0,
            f'compile failed ({compiled.returncode}): {compiled.stderr}')
    require(exe.is_file(), 'compiler produced no artifact')
    if kind == 'known-gap-compile-only':
        return
    try:
        result = run([str(exe)],
                     stdin=probe.get('stdin', ''),
                     timeout=1 if kind == 'known-gap-timeout' else 5)
    except subprocess.TimeoutExpired:
        require(kind == 'known-gap-timeout', 'unexpected execution timeout')
        return
    require(kind != 'known-gap-timeout',
            'loop terminated; flip G19 to the correct output oracle')
    if kind == 'known-gap-crash':
        # Crash class only: no signal number or UB-derived output is pinned.
        require(result.returncode < 0,
                f'expected signal termination, got {result.returncode}')
        require(
            'runtime error:' not in result.stderr,
            'located diagnostic appeared; flip crash gap to diagnostic test')
        return
    if kind == 'correct-runtime-error':
        require(result.returncode != 0, 'expected runtime failure')
        require(result.stderr == probe['stderr'],
                f'wrong stderr: {result.stderr!r}')
    else:
        require(result.returncode == 0,
                f'run failed ({result.returncode}): {result.stderr}')
        require(result.stderr == '', f'unexpected stderr: {result.stderr!r}')
    require(
        result.stdout == probe['stdout'],
        f"stdout {result.stdout!r}, expected {probe['stdout']!r}; update known-gap expectations only with the fixing change"
    )


def main():
    # Do not leave core files from deliberately crash-class probes.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    matrix = json.loads((TESTS / 'mathck_baseline.json').read_text())
    probes = matrix['probes']
    require(
        len({p['id']
             for p in probes}) == len(probes), 'duplicate probe IDs')
    require({int(re.match(r'G(\d+)', p['id'])[1])
             for p in probes} == set(range(1, 30)), 'matrix must cover G1–G29')
    count = 0
    failures = []
    with tempfile.TemporaryDirectory(prefix='mathck-baseline-') as directory:
        for probe in probes:
            for dialect in probe['dialects']:
                for opt in matrix['optimizations']:
                    label = f"{probe['id']} {dialect} O{opt} [{probe['kind']}]"
                    try:
                        check(probe, dialect, opt, Path(directory))
                    except (AssertionError,
                            subprocess.TimeoutExpired) as error:
                        failures.append(label)
                        print(f'FAIL {label}: {error}', flush=True)
                    else:
                        count += 1
                        print(f'PASS {label}', flush=True)
    require(not failures, f'{len(failures)} failures: {", ".join(failures)}')
    print(
        f'mathck baseline: {len(probes)} probes, {count} matrix cells passed (baseline {matrix["baseline"]})'
    )


if __name__ == '__main__':
    main()
