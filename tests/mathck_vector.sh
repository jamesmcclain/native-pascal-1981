#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK for integer VECTOR lanes and the VSUM/VPROD reductions, from
# checked-in fixtures whose expectations come from exact integer arithmetic,
# never from compiler output. Every integer element type, extended dialect,
# both settings, O0-O3. Lane + - * and negation are checked per lane under
# MATHCK+ (the lowest failing lane reports its own operands) and wrap under
# MATHCK-. Lane DIV/MOD have the scalar mandatory zero-divisor failure and
# safe MIN/-1. VSUM and VPROD fold left to right, each step checked under
# MATHCK+, and wrap under MATHCK-. Under tests/fixtures/mathck, per type:
#   vector_<type>_ok.pas/.out      boundary lanes that fit, same output under
#                                  both settings (prepended)
#   vector_<type>_cases.pas        failure/wrap cases, one per stdin case
#   vector_<type>_checked.expected / _unchecked.expected
#                                  exact transcripts under MATHCK+ / MATHCK-
#   vector_ir.pas                  the MATHCK- O0 IR shape
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
types=(INTEGER8 INTEGER INTEGER32 INTEGER64 WORD8 WORD WORD32 WORD64)
declare -A expect=([ok]=64 [case]=576 [ir]=1)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # opt source exe; never reuse a previous cell's binary
  rm -f "$3"
  bin/pascal1981 --dialect extended -O"$1" "$2" -o "$3" || die "compile $2 (O$1)"
}

type_unit() { # type flag
  local base=$fixtures/vector_${1,,} flag=$2 opt k status cases tag
  [ "$flag" = + ] && tag=checked || tag=unchecked
  printf '{$MATHCK%s}\n' "$flag" | cat - "$base"_ok.pas > "$dir/ok.pas"
  printf '{$MATHCK%s}\n' "$flag" | cat - "$base"_cases.pas > "$dir/cases.pas"
  mapfile -t cases < <(sed -n 's/^case //p' "$base"_$tag.expected)
  [ "${#cases[@]}" -gt 0 ] || die "$base: no cases"
  for opt in 0 1 2 3; do
    build "$opt" "$dir/ok.pas" "$dir/ok"
    status=0
    timeout 10 "$dir/ok" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "$1 ok MATHCK$flag O$opt: exit status $status"
    diff -u "$base"_ok.out "$dir/stdout" || die "$1 ok MATHCK$flag O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "$1 ok MATHCK$flag O$opt: stderr not empty"
    count ok
    build "$opt" "$dir/cases.pas" "$dir/cases"
    : > "$dir/transcript"
    for k in "${cases[@]}"; do
      status=0
      # The subshell absorbs bash's own "Aborted" job report.
      (timeout 10 "$dir/cases" <<< "$k" > "$dir/stdout" 2> "$dir/stderr"; exit) \
        2> /dev/null || status=$?
      [ "$status" -eq 0 ] || status=nonzero
      { printf 'case %s\nstatus: %s\nstdout:\n' "$k" "$status"
        cat "$dir/stdout"; echo 'stderr:'; cat "$dir/stderr"
      } >> "$dir/transcript"
      count case
    done
    diff -u "$base"_$tag.expected "$dir/transcript" || die "$1 cases MATHCK$flag O$opt"
  done
}

ir_unit() { # MATHCK- keeps vector + - * and reduce.add; DIV/MOD stay per lane
  local ir=$dir/ir.ll inst
  bin/pascal1981 --dialect extended -O0 -S "$fixtures/vector_ir.pas" -o "$ir" ||
    die "compile vector_ir.pas"
  ! grep -qF with.overflow "$ir" || die "IR: overflow intrinsic"
  ! grep -qF pas_math_overflow "$ir" || die "IR: overflow failure call"
  for inst in 'add <4 x i16>' 'sub <4 x i16>' 'mul <4 x i16>' llvm.vector.reduce.add; do
    grep -qF "$inst" "$ir" || die "IR: no $inst"
  done
  ! grep -qE '= s(div|rem) <' "$ir" || die "IR: vector division emitted"
  [ "$(grep -cF 'call void @pas_math_zero' "$ir" || true)" -eq 8 ] ||
    die "IR: pas_math_zero calls: $(grep -cF 'call void @pas_math_zero' "$ir" || true), expected 8"
  count ir
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for type in "${types[@]}"; do
  start "$type-checked" type_unit "$type" +
  start "$type-unchecked" type_unit "$type" -
done
start ir ir_unit
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
echo "PASS: MATHCK VECTOR lanes and VSUM/VPROD: $(( got[ok] + got[case] )) runtime" \
  "cells (every integer element type, both settings, O0-O3);" \
  "MATHCK- IR keeps vector + - * and has no vector division"
