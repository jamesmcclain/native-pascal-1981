#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# The suite index in tests/README.md matches the suites and their headers.
#
# tests/lib/index.sh generates the index from each suite's first header
# sentence; run `tests/lib/index.sh --update` after adding, removing or
# renaming a suite or changing that sentence.
tests/lib/index.sh > "$work/index"
sed -n '/^<!-- suite-index:begin/,/^<!-- suite-index:end -->$/p' tests/README.md |
  sed '1d;$d' > "$work/readme"
diff -u "$work/readme" "$work/index" ||
  die 'tests/README.md suite index is stale: run tests/lib/index.sh --update'
echo "PASS: suite index lists $(grep -c '^| [a-z]' "$work/index") suites"
