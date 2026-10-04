#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Executable G1-G29 gap inventory, not a claim that MATHCK is implemented.
# tests/mathck_baseline.json classifies one probe fixture per row (kind,
# dialects, and the expected diagnostic or output); every probe runs in
# each of its dialects at each listed optimization level. A known gap is
# pinned as it is, so a fix fails here until its row is reclassified in
# the same change. Each run is bounded by timeout (1 s for a known-gap
# timeout, 5 s otherwise); a crash-class probe must die by a signal with no
# located diagnostic, and no signal number or UB-derived output is pinned.
# Compilation is bounded at 30 s.
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
matrix=tests/mathck_baseline.json
workers=16
kinds=' known-gap-output known-gap-crash known-gap-compile-only known-gap-timeout
  known-gap-reject correct-reject correct-output out-of-scope-output
  correct-runtime-error '
kinds=${kinds//[[:space:]]/ } # one space-separated list for the membership test

die() { echo "FAIL: $*" >&2; exit 1; }

jq -e '[.probes[].id] | length == (unique | length)' "$matrix" > /dev/null || die 'duplicate probe IDs'
jq -e 'all(.probes[]; .name | type == "string" and length > 0)' "$matrix" > /dev/null \
  || die 'every probe needs a non-empty name'
jq -e '[.probes[].id | capture("^G(?<n>[0-9]+)").n | tonumber] | unique == [range(1; 30)]' \
  "$matrix" > /dev/null || die 'matrix must cover G1-G29'
probes=$(jq '.probes | length' "$matrix")
mapfile -t opts < <(jq -r '.optimizations[]' "$matrix")
[ "$probes" -gt 0 ] && [ "${#opts[@]}" -gt 0 ] || die 'empty matrix'

field() { # probe field: raw value, or nothing when absent
  jq -j --argjson i "$1" --arg f "$2" '.probes[$i] | if has($f) then .[$f] else empty end' "$matrix"
}

label() { # gap ID plus human-readable probe description
  echo "$(field "$1" id) $(field "$1" name)"
}

check() { # probe dialect opt cell: prints nothing on success, the reason otherwise
  local probe=$1 dialect=$2 opt=$3 cell=$4 kind status limit
  local -a command
  kind=$(field "$probe" kind)
  [[ $kinds == *" $kind "* ]] || { echo "unknown classification: $kind"; return; }
  command=(bin/pascal1981 --dialect "$dialect" -O"$opt" "tests/$(field "$probe" fixture)" -o "$cell/probe")
  # Known-gap compile-only probes are never executed here (none remain).
  [ "$kind" = known-gap-compile-only ] && command=(bin/pascal1981 -c "${command[@]:1}")
  status=0
  timeout 30 "${command[@]}" > /dev/null 2> "$cell/compile.err" || status=$?
  [ "$status" -ne 124 ] || { echo 'compile timed out'; return; }
  if [ "$kind" = known-gap-reject ] || [ "$kind" = correct-reject ]; then
    [ "$status" -ne 0 ] ||
      { echo 'unexpected compile acceptance; flip the gap expectation when fixed'; return; }
    grep -qF -- "$(field "$probe" diagnostic)" "$cell/compile.err" ||
      echo "wrong rejection diagnostic: $(< "$cell/compile.err")"
    return
  fi
  [ "$status" -eq 0 ] || { echo "compile failed ($status): $(< "$cell/compile.err")"; return; }
  [ -f "$cell/probe" ] || { echo 'compiler produced no artifact'; return; }
  [ "$kind" = known-gap-compile-only ] && return
  field "$probe" stdin > "$cell/stdin"
  [ "$kind" = known-gap-timeout ] && limit=1 || limit=5
  status=0
  # The subshell absorbs bash's own job report for crash-class probes.
  (timeout "$limit" "$cell/probe" < "$cell/stdin" > "$cell/stdout" 2> "$cell/stderr"; exit) \
    2> /dev/null || status=$?
  if [ "$status" -eq 124 ]; then
    [ "$kind" = known-gap-timeout ] || echo 'unexpected execution timeout'
    return
  fi
  [ "$kind" != known-gap-timeout ] ||
    { echo 'loop terminated; flip G19 to the correct output oracle'; return; }
  if [ "$kind" = known-gap-crash ]; then
    [ "$status" -gt 128 ] || { echo "expected signal termination, got $status"; return; }
    ! grep -qF 'runtime error:' "$cell/stderr" ||
      echo 'located diagnostic appeared; flip crash gap to diagnostic test'
    return
  fi
  if [ "$kind" = correct-runtime-error ]; then
    [ "$status" -ne 0 ] || { echo 'expected runtime failure'; return; }
    field "$probe" stderr | cmp -s - "$cell/stderr" ||
      { echo "wrong stderr: $(< "$cell/stderr")"; return; }
  else
    [ "$status" -eq 0 ] || { echo "run failed ($status): $(< "$cell/stderr")"; return; }
    [ ! -s "$cell/stderr" ] || { echo "unexpected stderr: $(< "$cell/stderr")"; return; }
  fi
  field "$probe" stdout | cmp -s - "$cell/stdout" ||
    echo "stdout $(< "$cell/stdout"), expected $(field "$probe" stdout); update known-gap expectations only with the fixing change"
}

probe_job() { # probe: one result line per dialect and level, in order
  local probe=$1 label kind dialect opt reason cell
  label=$(label "$probe"); kind=$(field "$probe" kind)
  : > "$work/results.$probe"
  while IFS= read -r dialect; do
    for opt in "${opts[@]}"; do
      cell=$work/cells/$probe-$dialect-$opt
      mkdir -p "$cell"
      reason=$(check "$probe" "$dialect" "$opt" "$cell")
      if [ -z "$reason" ]; then
        echo "PASS $label $dialect O$opt [$kind]" >> "$work/results.$probe"
      else
        echo "FAIL $label $dialect O$opt [$kind]: $reason" >> "$work/results.$probe"
      fi
    done
  done < <(jq -r --argjson i "$probe" '.probes[$i].dialects[]' "$matrix")
  touch "$work/done.$probe"
}

for ((probe = 0; probe < probes; probe++)); do
  while [ "$(jobs -rp | wc -l)" -ge "$workers" ]; do wait -n || true; done
  probe_job "$probe" &
done
wait
count=0
failures=0
for ((probe = 0; probe < probes; probe++)); do
  [ -e "$work/done.$probe" ] || { echo "FAIL probe $probe: no result" >&2; failures=$((failures + 1)); continue; }
  while IFS= read -r line; do
    echo "$line"
    if [[ $line == PASS* ]]; then count=$((count + 1)); else failures=$((failures + 1)); fi
  done < "$work/results.$probe"
done
[ "$failures" -eq 0 ] || die "$failures failures"
[ "$count" -gt 0 ] || die 'no matrix cells ran'
echo "mathck baseline: $probes probes, $count matrix cells passed (baseline $(jq -r .baseline "$matrix"))"
