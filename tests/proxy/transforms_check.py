#!/usr/bin/env python3
"""Differential test for proxycore's pure transforms.

Every transform in `src/proxycore.pas` replaced a function in the Python
completion proxy this port supersedes. `transforms_golden.json` is 776 jobs
and the answers that implementation gave for them, recorded while it was
still in the tree; this builds `transforms.pas` against the corpus and
compares.

    tests/proxy/transforms_check.py                  # build with bin/pascal1981
    tests/proxy/transforms_check.py path/to/compiler

The expected values were computed by calling the Python functions directly
rather than written by hand, so the corpus covers cases nobody thought to
predict -- every buffer crossed with every cursor, every echo snippet crossed
with six ways of retyping it. That is also why it cannot be re-recorded now
that the oracle is gone: the golden *is* the contract, and a mismatch means
the Pascal changed, not that the file is stale. A new case has to arrive with
an answer worked out by hand, which is the price of having deleted the
implementation it was checked against.

The corpus deliberately contains no NUL bytes. cJSON hands strings back as
NUL-terminated C strings, so a JSON value containing one is truncated there;
see proxycore.inc. The Python's own `sanitize_completion` stripped NUL
anyway, so nothing downstream of the parse ever depended on carrying one.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
GOLDEN = HERE / 'transforms_golden.json'


def load_corpus():
    """Return (jobs, expectations) as parallel lists."""
    cases = json.loads(GOLDEN.read_text(encoding='utf-8'))['cases']
    return [c['job'] for c in cases], [c['expected'] for c in cases]


def main() -> int:
    compiler = sys.argv[1] if len(sys.argv) > 1 else str(REPO / 'bin' /
                                                         'pascal1981')
    jobs, expected = load_corpus()

    with tempfile.TemporaryDirectory() as work:
        binary = str(Path(work) / 'transforms')
        subprocess.run([str(HERE / 'transforms.build.sh'), compiler, binary],
                       cwd=HERE,
                       check=True)
        completed = subprocess.run([binary],
                                   input=json.dumps(jobs).encode('utf-8'),
                                   stdout=subprocess.PIPE,
                                   check=True)

    actual = json.loads(completed.stdout.decode('utf-8'))
    if len(actual) != len(expected):
        print('transforms: got %d results for %d jobs' %
              (len(actual), len(expected)),
              file=sys.stderr)
        return 1

    failures = 0
    for job, want, got in zip(jobs, expected, actual):
        if got != want:
            failures += 1
            if failures <= 20:
                print('MISMATCH %s' % job.get('op'))
                print('  job:      %s' % json.dumps(job)[:400])
                print('  expected: %s' % json.dumps(want)[:400])
                print('  actual:   %s' % json.dumps(got)[:400])

    print('transforms: %d cases, %d mismatches' % (len(expected), failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
