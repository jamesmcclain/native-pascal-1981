#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# Programs that never overflow behave identically under MATHCK+ and MATHCK-.
#
# Corpus twin: every single-file fixture under tests/corpus/golden, tests/corpus/integration
# and tests/corpus/dialect (a sibling .build.sh marks a multi-file fixture, skipped)
# is compiled and run twice, with `{$MATHCK+}` and with `{$MATHCK-}` written
# in front of its first line (so line numbers do not move), at O0 and O2. The
# dialect is the fixture's first (tests/lib/fixture.sh: fixture_dialects);
# .stdin feeds standard input, .args gives one argument per line (an argument
# naming an existing path under the repository is passed as its absolute
# path), and each run gets its own empty working directory. Compile status
# and diagnostics (with the temporary source path replaced by <src>), exit
# status, stdout and stderr must match byte for byte. A link failure fails
# the suite even if both settings fail: matching broken links are not a
# success oracle. A fixture whose MATHCK+ run
# reports a MATHCK error is an overflowing program; its disabled twin is not
# an oracle here (the dedicated MATHCK suites pin the wrap), so it is
# counted, not compared. Compiles and runs are bounded at 60 s; a timeout on
# either side fails.
#
# Feature twin: tests/contract/fixtures/mathck/twin_extended.pas exercises every
# extended width, the scoped builtins, the SADDOK family, VECTOR lanes and
# reductions and FOR loops ending at each type's maximum, with no overflow;
# it must print twin_extended.out under both settings at O0-O3.
source tests/lib/fixture.sh
corpus_dirs=(tests/corpus/golden tests/corpus/integration tests/corpus/dialect)
mkdir "$work/results"

build_and_run() { # src flag opt cell: outcome files in cell/
  local src=$1 flag=$2 opt=$3 cell=$4 dialect status arg err input
  local -a args=() extra=()
  mkdir "$cell" "$cell/data"
  { printf '{$MATHCK%s}' "$flag"; cat "$src"; } > "$cell/src.pas"
  dialect=$(fixture_dialects "$src")
  dialect=${dialect%%$'\n'*} # the first, without a pipe that could break
  [ -n "$dialect" ] && args=(--dialect "$dialect")
  status=0
  timeout 60 bin/pascal1981 -O"$opt" "${args[@]}" "$cell/src.pas" -o "$cell/exe" \
    > /dev/null 2> "$cell/compile.raw" || status=$?
  [ "$status" -ne 124 ] || { printf 'timeout\n' > "$cell/outcome"; return; }
  # Diagnostics name the temporary file; compare them without it.
  IFS= read -r -d '' err < "$cell/compile.raw" || true
  printf '%s' "${err//"$cell/src.pas"/<src>}" > "$cell/compile"
  if grep -qF 'linker command failed' "$cell/compile"; then
    printf 'link\n%s\n' "$status" > "$cell/outcome"
    return
  fi
  if [ "$status" -ne 0 ]; then
    printf 'compile\n%s\n' "$status" > "$cell/outcome"
    return
  fi
  if [ -e "${src%.pas}.args" ]; then
    while IFS= read -r arg || [ -n "$arg" ]; do
      if [ -e "$ROOT/$arg" ]; then extra+=("$(realpath "$ROOT/$arg")"); else extra+=("$arg"); fi
    done < "${src%.pas}.args"
  fi
  input=/dev/null
  [ -e "${src%.pas}.stdin" ] && input=$ROOT/${src%.pas}.stdin
  status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (cd "$cell/data" && timeout 60 "$cell/exe" "${extra[@]}" < "$input" \
     > "$cell/stdout" 2> "$cell/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 124 ] || { printf 'timeout\n' > "$cell/outcome"; return; }
  printf 'run\n%s\n' "$status" > "$cell/outcome"
}

twin_job() { # index src opt: result is the outcome kind, or a FAIL line
  local index=$1 src=$2 opt=$3 base=$work/cells/$1 part kind
  mkdir -p "$base"
  build_and_run "$src" + "$opt" "$base/on"
  build_and_run "$src" - "$opt" "$base/off"
  kind=$(head -n 1 "$base/on/outcome")
  if [ "$kind" = link ] || [ "$(head -n 1 "$base/off/outcome")" = link ]; then
    echo "FAIL $src O$opt: link failure under MATHCK+/-" > "$work/results/$index"
    cat "$base/on/compile" "$base/off/compile" > "$work/results/$index.diff"
  elif [ "$kind" = run ] && grep -qF MATHCK "$base/on/stderr"; then
    echo overflowing > "$work/results/$index"
  elif [ "$kind" = timeout ] || [ "$(head -n 1 "$base/off/outcome")" = timeout ]; then
    echo "FAIL $src O$opt: timed out" > "$work/results/$index"
  else
    for part in outcome compile stdout stderr; do
      [ -e "$base/on/$part" ] || [ -e "$base/off/$part" ] || continue
      if ! cmp -s "$base/on/$part" "$base/off/$part"; then
        echo "FAIL $src O$opt: $part differs under MATHCK+/-" > "$work/results/$index"
        diff -u "$base/on/$part" "$base/off/$part" > "$work/results/$index.diff" 2>&1 || true
        return
      fi
    done
    echo "$kind" > "$work/results/$index"
  fi
  rm -rf "$base" # keep the workspace small across 584 cells
}

extended_job() { # index flag opt
  local index=$1 flag=$2 opt=$3 cell=$work/ext/$1 status=0
  mkdir -p "$cell"
  printf '{$MATHCK%s}\n' "$flag" | cat - tests/contract/fixtures/mathck/twin_extended.pas > "$cell/src.pas"
  if ! timeout 60 bin/pascal1981 --dialect extended -O"$opt" "$cell/src.pas" -o "$cell/exe" 2> "$cell/compile"; then
    echo "FAIL twin_extended MATHCK$flag O$opt: compile" > "$work/results/e$index"; return
  fi
  timeout 60 "$cell/exe" > "$cell/stdout" 2> "$cell/stderr" < /dev/null || status=$?
  if [ "$status" -ne 0 ] || [ -s "$cell/stderr" ] ||
     ! cmp -s tests/contract/fixtures/mathck/twin_extended.out "$cell/stdout"; then
    echo "FAIL twin_extended MATHCK$flag O$opt: status $status or output" > "$work/results/e$index"
  else
    echo extended > "$work/results/e$index"
  fi
}

jobs_total=0
index=0
for flag in + -; do
  for opt in 0 1 2 3; do
    spawn extended_job "$index" "$flag" "$opt"
    index=$((index + 1))
  done
done
extended_total=$index
index=0
for directory in "${corpus_dirs[@]}"; do
  found=0
  for src in "$directory"/*.pas; do
    [ -e "$src" ] || continue
    [ -e "${src%.pas}.build.sh" ] && continue
    found=$((found + 1))
    for opt in 0 2; do
      spawn twin_job "$index" "$src" "$opt"
      index=$((index + 1))
    done
  done
  [ "$found" -gt 0 ] || { echo "FAIL: no single-file fixtures in $directory" >&2; exit 1; }
done
jobs_total=$index
wait

declare -A got=()
failed=0
for ((i = 0; i < extended_total; i++)); do
  [ -e "$work/results/e$i" ] || { echo "FAIL: extended cell $i left no result" >&2; failed=1; continue; }
  result=$(< "$work/results/e$i")
  [[ $result == FAIL* ]] && { echo "$result" >&2; failed=1; continue; }
  got[$result]=$(( ${got[$result]:-0} + 1 ))
done
for ((i = 0; i < jobs_total; i++)); do
  [ -e "$work/results/$i" ] || { echo "FAIL: corpus cell $i left no result" >&2; failed=1; continue; }
  result=$(< "$work/results/$i")
  if [[ $result == FAIL* ]]; then
    echo "$result" >&2
    [ -e "$work/results/$i.diff" ] && head -n 40 "$work/results/$i.diff" >&2
    failed=1; continue
  fi
  got[$result]=$(( ${got[$result]:-0} + 1 ))
done
[ "$failed" -eq 0 ] || exit 1
[ "${got[extended]:-0}" -eq 8 ] || { echo "FAIL: ${got[extended]:-0} extended cells, expected 8" >&2; exit 1; }
echo "PASS: MATHCK on/off twins: ${got[extended]} extended-fixture cells (all widths," \
  "builtins, SADDOK family, VECTOR, FOR to the maximum; O0-O3); corpus fixtures at" \
  "O0/O2: ${got[run]:-0} runs, ${got[compile]:-0} rejections and ${got[link]:-0} link" \
  "failures identical under MATHCK+/-, ${got[overflowing]:-0} overflowing (not compared)"
