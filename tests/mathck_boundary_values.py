#!/usr/bin/env python3
"""Legitimate boundary values never trap under MATHCK+.

tests/fixtures/mathck/boundary_values.pas computes 32767, -32768, 0 and
65535 through every checked 16-bit operation, the listed edge cases
(-32767 - 1, -16384 * 2, PRED(-32767), -32767 + (-1), MIN MOD -1,
-7 DIV 2, ...) from variables, and the same values as folded constants.
-32768 is ordinary data (the inherited non-sentinel premise), so it must be
produced and consumed at the operator level without a trap. Both dialects,
O0-O3, both settings, exact output. At O0 the MATHCK+ IR must really check
every variable operation (a fixed count of failure branches); MATHCK- has no
overflow checks, only the mandatory zero-divisor failures.
"""
import resource
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathck_overflow import OPTS, ROOT, run

FIXTURE = ROOT / 'tests/fixtures/mathck/boundary_values.pas'
# Checked operations on variables in the fixture's body (each has one
# pas_math_overflow failure block at O0); DIV/MOD by a variable add a
# zero-divisor block under either setting.
OVERFLOW_SITES = 44
ZERO_SITES = 12


def compile_source(work, tag, flag, dialect, opt, ir=False):
    path = work / f'{tag}.pas'
    out = work / (f'{tag}.ll' if ir else tag)
    path.write_text(f'{{$MATHCK{flag}}}\n' + FIXTURE.read_text())
    built = run(['bin/pascal1981', '--dialect', dialect, f'-O{opt}'] +
                (['-S'] if ir else []) +
                [str(path), '-o', str(out)])
    assert built.returncode == 0, (tag, built.stderr)
    return out


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    expected = FIXTURE.with_suffix('.out').read_text()
    jobs = [(flag, dialect, opt) for flag in '+-'
            for dialect in ('vintage', 'extended') for opt in OPTS]
    with tempfile.TemporaryDirectory(prefix='mathck-boundary-') as tmp:
        work = Path(tmp)

        def one(job):
            flag, dialect, opt = job
            exe = compile_source(work, f'bv_{flag == "+"}_{dialect}_O{opt}',
                                 flag, dialect, opt)
            result = run([str(exe)])
            assert (result.returncode, result.stdout,
                    result.stderr) == (0, expected, ''), (job, result)

        with ThreadPoolExecutor(max_workers=16) as pool:
            list(pool.map(one, jobs))
        for flag in '+-':
            text = compile_source(work,
                                  f'ir_{flag == "+"}',
                                  flag,
                                  'vintage',
                                  0,
                                  ir=True).read_text()
            overflow = text.count('call void @pas_math_overflow')
            zero = text.count('call void @pas_math_zero')
            assert zero == ZERO_SITES, (flag, zero)
            if flag == '+':
                assert overflow == OVERFLOW_SITES, overflow
            else:
                assert overflow == 0 and '.with.overflow' not in text, overflow
    print(f'PASS: MATHCK boundary values: {len(jobs)} cells (32767, -32768, '
          '0, 65535 and the listed edge results from variables and '
          'constants never trap; vintage/extended, O0-O3, both settings); '
          f'O0 IR checks all {OVERFLOW_SITES} variable operations under '
          'MATHCK+ and none under MATHCK-')


if __name__ == '__main__':
    main()
