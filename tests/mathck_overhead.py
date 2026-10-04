#!/usr/bin/env python3
"""Opt-in MATHCK measurement, not a timing pass/fail gate. Run from any cwd.

Each tests/fixtures/mathck/bench_*.pas workload is compiled with its
`{$MATHCK+}` and again with `{$MATHCK-}` at O0 and O2. MATHCK- is a true
unchecked comparator: wrapping arithmetic with no overflow intrinsics (the
mandatory zero-divisor checks stay in both builds). No workload overflows,
so both builds must print the same exact output. Results go to stdout as
JSON; tests/README.md#opt-in-overhead-measurements describes the method and
retained measurement snapshots.
"""
import argparse
import json
import platform
import re
import statistics
import subprocess
import sys as _temp_sys
import tempfile
from pathlib import Path as _TempPath

_temp_sys.path.insert(
    0, str(_TempPath(__file__).resolve().parents[1] / 'scripts'))
import time
from pathlib import Path

import native_temp  # owns this process's temporary workspace

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repeats', type=int, default=7)
args = parser.parse_args()
if args.repeats < 3:
    parser.error('--repeats must be at least 3')

# (fixture stem, dialect, exact stdout for input "1").
WORKLOADS = [('scalar', 'vintage', '4665\n'),
             ('builtins', 'vintage', '-8915\n'),
             ('wide', 'extended', '6594377559292\n'),
             ('vector', 'extended', '28 -28\n')]
VECTOR_OP = re.compile(r'= (add|sub|mul) <\d+ x i\d+>')


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
    'repeats':
    args.repeats,
    'comparison':
    'MATHCK+ versus MATHCK- (unchecked, wrapping); same source otherwise',
    'timing':
    'wall seconds including process startup and GNU time launcher; warmup excluded',
    'cases': [],
}
with tempfile.TemporaryDirectory(prefix='mathck-overhead-') as tmp:
    work = Path(tmp)
    for name, dialect, expected in WORKLOADS:
        source = (repo / 'tests/fixtures/mathck' /
                  f'bench_{name}.pas').read_text()
        assert '{$MATHCK+}' in source, name
        for opt in (0, 2):
            cases = {}
            for mode in ('off', 'on'):
                pas = work / f'{name}-{mode}.pas'
                pas.write_text(source if mode == 'on' else source.
                               replace('{$MATHCK+}', '{$MATHCK-}'))
                binary = work / f'{name}-{mode}'
                ir = work / f'{name}-{mode}.ll'
                common = [
                    str(repo / 'bin/pascal1981'), '--dialect', dialect,
                    f'-O{opt}',
                    str(pas)
                ]
                command(common + ['-o', str(binary)])
                command(common + ['-S', '-o', str(ir)])
                ir_text = ir.read_text()
                text, data, bss = map(
                    int,
                    command(['size', str(binary)]).splitlines()[1].split()[:3])
                cases[mode] = {
                    'elf_bytes':
                    binary.stat().st_size,
                    'text_bytes':
                    text,
                    'data_bytes':
                    data,
                    'bss_bytes':
                    bss,
                    'ir_bytes':
                    len(ir_text),
                    # Failure calls left after optimization at this level.
                    'ir_overflow_failure_calls':
                    ir_text.count('call void @pas_math_overflow'),
                    'ir_overflow_intrinsics':
                    len(
                        re.findall(
                            r'call \{ [^}]*\} @llvm\.[su]\w+\.with\.'
                            r'overflow', ir_text)),
                    'ir_vector_integer_ops':
                    len(VECTOR_OP.findall(ir_text)),
                    'seconds': [],
                    'peak_rss_kib': []
                }
            assert cases['off']['ir_overflow_intrinsics'] == 0, name

            def run(mode, measured):
                start = time.perf_counter()
                result = subprocess.run([
                    '/usr/bin/time', '-f', '%M', '-o',
                    str(work / 'rss'),
                    str(work / f'{name}-{mode}')
                ],
                                        input='1\n',
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
                'dialect':
                dialect,
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
