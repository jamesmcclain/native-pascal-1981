#!/usr/bin/env bash
# Run make targets with -k (every group runs even after one fails), keep the
# full output in a log, and end with a summary naming every failed make
# target and failing check, so a failure cannot scroll by unnoticed.
# Usage: scripts/test-report.sh LOG TARGET...
set -uo pipefail
log=$1; shift
make=${MAKE:-make}
mkdir -p "$(dirname "$log")"
"$make" -k "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# "make[1]: *** [Makefile:250: native-suite-initck_heap] Error 1"
mapfile -t targets < <(sed -nE 's/^g?make(\[[0-9]+\])?: \*\*\* \[[^]]*: ([^]]+)\] Error.*/\2/p' "$log" |
  awk '!seen[$0]++')
mapfile -t checks < <(grep -E '^(FAIL|ERROR)(:| )|^FAILED ' "$log" | awk '!seen[$0]++')

rule='======================================================================'
echo
echo "$rule"
if [ "$status" -eq 0 ]; then
  echo "${TEST_REPORT_LABEL:-make $*}: PASSED"
else
  echo "${TEST_REPORT_LABEL:-make $*}: FAILED (make exit status $status)"
  if [ "${#targets[@]}" -gt 0 ]; then
    echo
    echo "Failed make targets:"
    printf '  %s\n' "${targets[@]}"
  fi
  if [ "${#checks[@]}" -gt 0 ]; then
    echo
    echo "Failing checks (${#checks[@]}):"
    printf '  %s\n' "${checks[@]:0:60}"
    [ "${#checks[@]}" -le 60 ] || echo "  ... $(( ${#checks[@]} - 60 )) more"
  fi
fi
echo
echo "Full log: $log"
echo "$rule"
exit "$status"
