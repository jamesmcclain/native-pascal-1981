#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK diagnostics are located and distinct from the other checks'. Every
# MATHCK runtime class (signed/unsigned overflow in an operator, unary minus,
# a scoped builtin and a VECTOR reduction; signed/unsigned division by zero)
# prints exactly one `runtime error: MATHCK ...` line carrying the operator
# or function-name token's line and column, after flushing stdout. The
# neighbouring failures (RANGECK subrange stores and SUCC/PRED domains,
# INDEXCK bounds, INITCK reads, TRUNC/ROUND conversion) keep their own texts,
# never the MATHCK stem. RANGECK and INDEXCK messages are still unlocated
# (their own records decide that). Exact text at O0 and O2, from fixtures in
# tests/fixtures/mathck:
#   diag.pas                     one failing statement per stdin case; the
#                                suite prepends MATHCK+ or MATHCK-
#   diag_checked.expected        MATHCK+ transcript, every case
#   diag_unchecked.expected      MATHCK- transcript, the MATHCK cases: zero
#                                divisors still fail, overflow wraps
#   diag_initck.pas/.err         an INITCK read in a procedure
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
mathck_cases=' 0 1 2 3 4 5 6 ' # the rest of diag.pas are other checks
declare -A expect=([mathck]=28 [other]=8 [initck]=2)
stem='runtime error: MATHCK (signed|unsigned) (overflow|division by zero) in [^ ]+ at line [0-9]+ column [0-9]+ \(.+\)'

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # opt source exe; never reuse a previous cell's binary
  rm -f "$3"
  bin/pascal1981 --dialect extended -O"$1" "$2" -o "$3" || die "compile $2 (O$1)"
}

routed() { # label kind: one stderr line, the MATHCK stem exactly when kind=mathck
  [ "$(wc -l < "$dir/stderr")" -eq 1 ] || die "$1: stderr is not one line"
  if [ "$2" = mathck ]; then
    grep -qEx "$stem" "$dir/stderr" || die "$1: not the MATHCK stem"
  else
    ! grep -qF MATHCK "$dir/stderr" || die "$1: MATHCK in another check's text"
  fi
}

diag_unit() { # flag opt
  local flag=$1 opt=$2 tag k status kind cases
  [ "$flag" = + ] && tag=checked || tag=unchecked
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/diag.pas" > "$dir/diag.pas"
  mapfile -t cases < <(sed -n 's/^case //p' "$fixtures/diag_$tag.expected")
  [ "${#cases[@]}" -gt 0 ] || die "diag_$tag.expected: no cases"
  build "$opt" "$dir/diag.pas" "$dir/diag"
  : > "$dir/transcript"
  for k in "${cases[@]}"; do
    status=0
    # The subshell absorbs bash's own "Aborted" job report.
    (timeout 10 "$dir/diag" <<< "$k" > "$dir/stdout" 2> "$dir/stderr"; exit) \
      2> /dev/null || status=$?
    [[ $mathck_cases == *" $k "* ]] && kind=mathck || kind=other
    if [ "$status" -ne 0 ]; then
      routed "case $k MATHCK$flag O$opt" "$kind"
      status=nonzero
    fi
    { printf 'case %s\nstatus: %s\nstdout:\n' "$k" "$status"
      cat "$dir/stdout"; echo 'stderr:'; cat "$dir/stderr"
    } >> "$dir/transcript"
    count "$kind"
  done
  diff -u "$fixtures/diag_$tag.expected" "$dir/transcript" || die "MATHCK$flag O$opt"
}

initck_unit() { # opt
  local status=0
  build "$1" "$fixtures/diag_initck.pas" "$dir/initck"
  (timeout 10 "$dir/initck" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "INITCK O$1: did not fail"
  printf 'prefix\n' | diff -u - "$dir/stdout" || die "INITCK O$1: stdout"
  diff -u "$fixtures/diag_initck.err" "$dir/stderr" || die "INITCK O$1: stderr"
  routed "INITCK O$1" other
  count initck
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for opt in 0 2; do
  start "checked-O$opt" diag_unit + "$opt"
  start "unchecked-O$opt" diag_unit - "$opt"
  start "initck-O$opt" initck_unit "$opt"
done
wait
failed=0
for log in "$work"/*.log; do
  name=$(basename "$log" .log)
  if [ ! -e "$work/$name/passed" ]; then
    echo "FAIL: unit $name" >&2; cat "$log" >&2; failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
declare -A got=()
while read -r key; do got[$key]=$(( ${got[$key]:-0} + 1 )); done < <(cat "$work"/*/counts)
for key in "${!expect[@]}"; do
  [ "${got[$key]:-0}" -eq "${expect[$key]}" ] ||
    die "$key cells: ${got[$key]:-0}, expected ${expect[$key]}"
done
[ "${#got[@]}" -eq "${#expect[@]}" ] || die "unexpected cell kinds: ${!got[*]}"
echo "PASS: MATHCK diagnostics: $(( got[mathck] + got[other] + got[initck] )) cells" \
  "(each MATHCK class located at its token under MATHCK+, zero divisors under" \
  "MATHCK- too, overflow wraps under MATHCK-; RANGECK/INDEXCK/INITCK/TRUNC" \
  "failures keep distinct texts; O0/O2)"
