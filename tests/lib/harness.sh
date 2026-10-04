# Shared prologue for every shell test suite. Source it first:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
#
# It gives every suite the same environment however it is started:
#  - re-executes the suite under scripts/test-env.sh (crash-report
#    suppression, quiet host compiler) unless it already runs there, so a
#    suite run by hand behaves as it does under `make test`;
#  - runs it under scripts/temp-env.sh's supervisor, which owns a private
#    TMPDIR and removes it however the suite exits;
#  - sets strict mode and changes to the repository root.
# It defines $ROOT, $work (an empty scratch directory) and $HARNESS_JOBS
# (how many processes this suite may run at once: PASCAL_TEST_JOBS, set by
# tests/lib/schedule.sh, else every CPU).
#
# The suite contract: exit status 0 means pass. Each failure prints a line
# starting "FAIL: " and each skipped check a line starting "SKIP: ", which
# the scheduler collects into its summary.
if [[ -z ${PASCAL_TEST_ENV:-} ]]; then
  exec "$(dirname "${BASH_SOURCE[0]}")/../../scripts/test-env.sh" \
    bash "${BASH_SOURCE[-1]}" "$@"
fi
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/temp-env.sh"
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
work=$(mktemp -d)
HARNESS_JOBS=${PASCAL_TEST_JOBS:-$(nproc)}

# Suites never build what they test: `make test` builds it first. A suite
# run by hand states what is missing instead.
require() { # repository-relative path...
  local path
  for path; do
    [ -e "$ROOT/$path" ] || die "$path is not built; run make (make test builds it)"
  done
}

# Reporting. die ends the suite at the first failure; fail records one and
# carries on, and finish then ends the suite with the tally. pass, fail and
# skip take a check name and an optional reason; pass with no name counts a
# check silently.
harness_passed=0 harness_failed=0 harness_skipped=0
die() { echo "FAIL: $*" >&2; exit 1; }
pass() {
  [ "$#" -eq 0 ] || echo "PASS: $1${2:+: $2}"
  harness_passed=$((harness_passed + 1))
}
fail() { echo "FAIL: $1${2:+: $2}" >&2; harness_failed=$((harness_failed + 1)); }
skip() { echo "SKIP: $1${2:+: $2}"; harness_skipped=$((harness_skipped + 1)); }
finish() { # [label]: print the tally, exit 1 if anything failed
  echo "${1:-$(basename "$0" .sh)}: $harness_passed passed," \
    "$harness_failed failed, $harness_skipped skipped"
  exit $((harness_failed > 0))
}

# Parallel work. `spawn COMMAND...` runs COMMAND in the background once
# fewer than $HARNESS_JOBS background jobs are running; `wait` collects them.
spawn() {
  while [ "$(jobs -rp | wc -l)" -ge "$HARNESS_JOBS" ]; do wait -n || true; done
  "$@" &
}

# Parallel units. `unit NAME COMMAND...` spawns COMMAND with $dir set to a
# fresh directory of its own and its output in a log. Inside a unit,
# `count KIND [N]` records N (default 1) cells of KIND. units_wait waits
# for every unit, prints the log of each that failed and exits 1 if any
# did, sums the counts into the associative array got, and, when the suite
# has declared an associative array expect, requires got to equal it
# exactly.
unit() {
  local name=$1
  shift
  dir=$work/units/$name
  mkdir -p "$dir"
  spawn harness_unit "$@"
}
harness_unit() { ("$@" && touch "$dir/passed") > "$dir.log" 2>&1; }
count() { echo "$1 ${2:-1}" >> "$dir/counts"; }
units_wait() {
  wait
  local log name failed=0 key n
  for log in "$work"/units/*.log; do
    name=$(basename "$log" .log)
    if [ ! -e "$work/units/$name/passed" ]; then
      echo "FAIL: unit $name" >&2
      cat "$log" >&2
      failed=1
    fi
  done
  [ "$failed" -eq 0 ] || exit 1
  declare -gA got=()
  while read -r key n; do
    got[$key]=$((${got[$key]:-0} + n))
  done < <(cat "$work"/units/*/counts 2> /dev/null)
  if declare -p expect &> /dev/null; then
    for key in "${!expect[@]}"; do
      [ "${got[$key]:-0}" -eq "${expect[$key]}" ] ||
        die "$key cells: ${got[$key]:-0}, expected ${expect[$key]}"
    done
    [ "${#got[@]}" -eq "${#expect[@]}" ] || die "unexpected cell kinds: ${!got[*]}"
  fi
}
