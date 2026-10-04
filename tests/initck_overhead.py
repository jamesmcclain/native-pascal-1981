#!/usr/bin/env python3
"""Opt-in INITCK measurement, not a timing pass/fail gate. Run from any cwd."""
import argparse
import json
import platform
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repeats', type=int, default=7)
args = parser.parse_args()
if args.repeats < 3:
    parser.error('--repeats must be at least 3')


def command(argv):
    result = subprocess.run(argv, cwd=repo, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{argv}: {result.stderr}')
    if result.stderr:
        raise RuntimeError(result.stderr)
    return result.stdout


report = {
    'revision':
    command(['git', 'rev-parse', 'HEAD']).strip(),
    'platform':
    platform.platform(),
    'cpu':
    next((line.split(':', 1)[1].strip()
          for line in Path('/proc/cpuinfo').read_text().splitlines()
          if line.startswith('model name')), 'unknown'),
    'clang':
    command(['clang', '--version']).splitlines()[0],
    'dialect':
    'vintage',
    'repeats':
    args.repeats,
    'comparison':
    'on versus off; BOTH track state, not an uninstrumented baseline',
    'timing':
    'wall seconds including process startup and GNU time launcher; warmup excluded',
    'cases': [],
}
with tempfile.TemporaryDirectory(prefix='initck-overhead-') as tmp:
    work = Path(tmp)
    command([
        'clang', '-O2', 'tests/initck_bench_memory.c',
        'runtime/build/libpascalrt.a', '-Wl,--wrap=calloc', '-Wl,--wrap=free',
        '-o',
        str(work / 'memory')
    ])
    report['heap_allocation_probe'] = json.loads(
        command([str(work / 'memory')]))
    for name, expected in [('scalar', '0\n'), ('aggregate', '0:7\n'),
                           ('heap', '1\n')]:
        source = (repo / 'tests/fixtures' /
                  f'initck_bench_{name}.pas').read_text()
        for opt in (0, 2):
            cases = {}
            for mode in ('off', 'on'):
                pas = work / f'{name}-{mode}.pas'
                pas.write_text(source if mode == 'on' else source.
                               replace('{$INITCK+}', '{$INITCK-}'))
                binary = work / f'{name}-{mode}'
                ir = work / f'{name}-{mode}.ll'
                common = [
                    str(repo / 'bin/pascal1981'), '--dialect', 'vintage',
                    f'-O{opt}',
                    str(pas)
                ]
                command(common + ['-o', str(binary)])
                command(common + ['-S', '-o', str(ir)])
                text, data, bss = map(
                    int,
                    command(['size', str(binary)]).splitlines()[1].split()[:3])
                cases[mode] = {
                    'elf_bytes': binary.stat().st_size,
                    'text_bytes': text,
                    'data_bytes': data,
                    'bss_bytes': bss,
                    'ir_bytes': ir.stat().st_size,
                    'seconds': [],
                    'peak_rss_kib': []
                }

            def run(mode, measured):
                start = time.perf_counter()
                result = subprocess.run([
                    '/usr/bin/time', '-f', '%M', '-o',
                    str(work / 'rss'),
                    str(work / f'{name}-{mode}')
                ],
                                        input='0\n',
                                        text=True,
                                        capture_output=True,
                                        check=True)
                elapsed = time.perf_counter() - start
                assert result.stdout == expected, (name, mode, result.stdout)
                assert not result.stderr, result.stderr
                if measured:
                    cases[mode]['seconds'].append(elapsed)
                    cases[mode]['peak_rss_kib'].append(
                        int((work / 'rss').read_text()))

            for mode in ('off', 'on'):
                run(mode, False)
            for repeat in range(args.repeats):
                for mode in (('off', 'on') if repeat % 2 == 0 else
                             ('on', 'off')):
                    run(mode, True)
            for case in cases.values():
                case['median_seconds'] = statistics.median(case['seconds'])
                case['median_peak_rss_kib'] = statistics.median(
                    case['peak_rss_kib'])
            report['cases'].append({
                'workload':
                name,
                'optimization':
                opt,
                'modes':
                cases,
                'on_off_time_ratio':
                cases['on']['median_seconds'] / cases['off']['median_seconds'],
                'text_delta_bytes':
                cases['on']['text_bytes'] - cases['off']['text_bytes'],
            })
print(json.dumps(report, indent=2))
