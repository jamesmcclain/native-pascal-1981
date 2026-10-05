#!/usr/bin/env bash
# Run test suites in parallel and report on them.
#
#   tests/lib/schedule.sh [-j N] [-v] SELECTOR...
#   tests/lib/schedule.sh --summary
#
# A suite is a *.sh or *.py file directly inside a tier directory,
# tests/<tier>/; subdirectories hold that tier's data. A SELECTOR is a tier
# name (check, unit, corpus, contract, service, optional), a suite name
# (mathck_vector) or a suite path. Suites start longest first, by the time
# each took on its previous run.
#
# One budget of N processes (default TEST_JOBS, else every CPU) is shared by
# the suites running and the work inside each. A suite costs 1, unless a
# line of its own reads `# schedule: parallel`: such a suite fans out, so it
# costs, and is told in PASCAL_TEST_JOBS it may use, a share of the budget
# (TEST_PARALLEL_JOBS, default half of N). Every waiting suite whose cost
# fits what is left starts, in order. Each runs from the repository root
# under scripts/test-env.sh,
# with its output kept in build/test-results/<suite>.log; -v also prints it
# when the suite ends. One line per suite reports the result as it ends,
# and the run ends with the failures and skips of this batch.
#
# --summary reports on every suite with a result in build/test-results/:
# `make test` clears that directory, schedules each group of tiers as its
# tools are built, and ends with the summary. Exit status: 0 when every
# suite reported on passed.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
tiers=(check unit corpus contract service optional)
results=build/test-results
times=build/test-times
mkdir -p "$results"

budget=${TEST_JOBS:-$(nproc)}
verbose=0
summary=0
selectors=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -j) budget=$2; shift 2 ;;
    -j*) budget=${1#-j}; shift ;;
    -v) verbose=1; shift ;;
    --summary) summary=1; shift ;;
    -h|--help) sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
    -*) echo "schedule: unknown option $1" >&2; exit 2 ;;
    *) selectors+=("$1"); shift ;;
  esac
done

suite_files() { # tier: its suites, sorted
  find "tests/$1" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) | sort
}

# Report on suites (paths). Prints the failing and skipping checks of each,
# and returns 1 if any failed or has no result.
report() {
  local suite name status bad=0 passed=0 skips
  local -a failed=() skipped=()
  for suite; do
    name=$(basename "${suite%.*}")
    status=$(cat "$results/$name.status" 2> /dev/null || echo missing)
    if [ "$status" = 0 ]; then
      passed=$((passed + 1))
    else
      failed+=("$suite")
    fi
    skips=$(grep -c '^SKIP' "$results/$name.log" 2> /dev/null)
    [ "${skips:-0}" -eq 0 ] || skipped+=("$suite ($skips skipped)")
  done
  if [ "${#skipped[@]}" -gt 0 ]; then
    echo
    echo "Suites that skipped checks (see their logs):"
    printf '  %s\n' "${skipped[@]}"
  fi
  for suite in "${failed[@]}"; do
    name=$(basename "${suite%.*}")
    echo
    echo "FAILED: $suite (exit status $(cat "$results/$name.status" 2> /dev/null || echo 'none: it did not run'))"
    if [ -f "$results/$name.log" ]; then
      grep -E '^(FAIL|ERROR)(:| )|^FAILED ' "$results/$name.log" | head -n 20 | sed 's/^/  /'
      echo "  full log: $results/$name.log"
    fi
    bad=1
  done
  echo
  if [ "${#failed[@]}" -eq 0 ]; then
    echo "$passed of $# suites passed"
  else
    echo "$passed of $# suites passed, ${#failed[@]} failed"
  fi
  return "$bad"
}

if [ "$summary" = 1 ]; then
  mapfile -t suites < <(for tier in "${tiers[@]}"; do suite_files "$tier"; done |
    while read -r suite; do
      [ -e "$results/$(basename "${suite%.*}").status" ] && echo "$suite"
    done)
  rule='======================================================================'
  echo "$rule"
  report "${suites[@]}"
  status=$?
  [ "$status" -eq 0 ] && echo 'make test: PASSED' || echo 'make test: FAILED'
  echo "$rule"
  exit "$status"
fi

[ "${#selectors[@]}" -gt 0 ] || { echo "usage: $0 [-j N] [-v] SELECTOR... | --summary" >&2; exit 2; }
suites=()
for selector in "${selectors[@]}"; do
  if [ -d "tests/$selector" ] && [[ " ${tiers[*]} " = *" $selector "* ]]; then
    mapfile -t -O "${#suites[@]}" suites < <(suite_files "$selector")
  elif [ -f "$selector" ]; then
    suites+=("${selector#./}")
  else
    match=$(for tier in "${tiers[@]}"; do suite_files "$tier"; done |
      grep -E "/$selector\.(sh|py)\$")
    [ -n "$match" ] || { echo "schedule: no tier or suite named $selector" >&2; exit 2; }
    suites+=("$match")
  fi
done

# Longest first; a suite with no recorded time first of all.
declare -A secs=()
if [ -f "$times" ]; then
  while read -r name took; do secs[$name]=$took; done < "$times"
fi
mapfile -t suites < <(for suite in "${suites[@]}"; do
  printf '%s %s\n' "${secs[$(basename "${suite%.*}")]:-999999}" "$suite"
done | sort -k1,1nr -k2 | cut -d' ' -f2-)

share=${TEST_PARALLEL_JOBS:-$((budget / 2))}
[ "$share" -ge 1 ] || share=1
[ "$share" -le "$budget" ] || share=$budget
cost_of() { # suite: what it costs from the budget
  if grep -qx '# schedule: parallel' "$1"; then echo "$share"; else echo 1; fi
}

declare -A started=() suite_of=() cost=()
used=0
launch() {
  local suite=$1 name interpreter
  name=$(basename "${suite%.*}")
  used=$((used + cost[$suite]))
  case "$suite" in *.py) interpreter=python3 ;; *) interpreter=bash ;; esac
  rm -f "$results/$name.status"
  # A non-interactive shell starts background jobs with SIGINT and SIGQUIT
  # ignored, which exec preserves; restore them so suites that test signal
  # handling see the defaults. setsid gives the suite its own process group
  # for `interrupted` to stop.
  (
    trap - INT QUIT
    PASCAL_TEST_JOBS=${cost[$suite]} exec setsid scripts/test-env.sh "$interpreter" "$suite"
  ) < /dev/null > "$results/$name.log" 2>&1 &
  suite_of[$!]=$suite
  started[$!]=$EPOCHREALTIME
}
finished() { # pid status
  local suite=${suite_of[$1]} name took
  name=$(basename "${suite%.*}")
  took=$(awk -v a="${started[$1]}" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.1f", b - a }')
  echo "$2" > "$results/$name.status"
  printf '%s %s\n' "$name" "$took" >> "$times.new"
  if [ "$2" -eq 0 ]; then
    printf 'PASS %7ss  %s\n' "$took" "$suite"
  else
    printf 'FAIL %7ss  %s\n' "$took" "$suite"
  fi
  [ "$verbose" = 0 ] || sed 's/^/    /' "$results/$name.log"
  used=$((used - cost[$suite]))
  unset "suite_of[$1]" "started[$1]"
}
interrupted() {
  local pid
  for pid in "${!suite_of[@]}"; do kill -TERM -- "-$pid" 2> /dev/null; done
  wait
  exit 130
}
trap interrupted INT TERM

: > "$times.new"
# Start, in order, every waiting suite that fits; when none does, wait for
# a running one to end.
for suite in "${suites[@]}"; do cost[$suite]=$(cost_of "$suite"); done
queue=("${suites[@]}")
while [ "${#queue[@]}" -gt 0 ] || [ "${#suite_of[@]}" -gt 0 ]; do
  waiting=()
  for suite in "${queue[@]}"; do
    if [ $((used + cost[$suite])) -le "$budget" ]; then
      launch "$suite"
    else
      waiting+=("$suite")
    fi
  done
  queue=("${waiting[@]}")
  if [ "${#suite_of[@]}" -gt 0 ]; then
    wait -n -p pid
    finished "$pid" "$?"
  fi
done

# Keep the latest time of every suite, for the next run's ordering.
if [ -f "$times" ]; then
  awk 'NR == FNR { new[$1] = 1; print; next } !($1 in new)' "$times.new" "$times" > "$times.tmp"
else
  cp "$times.new" "$times.tmp"
fi
mv "$times.tmp" "$times"
rm -f "$times.new"

report "${suites[@]}"
