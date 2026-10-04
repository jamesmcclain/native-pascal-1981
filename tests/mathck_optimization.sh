#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK optimization never weakens the runtime contract. Folding: the
# codegen emits every check; LLVM may delete one only where it proves the
# operation cannot overflow. In fold.pas the FOR loops have constant bounds,
# so their `i + 1`, `i * 2 - 1` and `-i` cannot leave INTEGER and the O1-O3
# objects keep no failure call for them, while the checks LLVM cannot bound
# (the accumulations into k and the operations on the value read at run
# time) stay. The compiler adds no range facts of its own: constant FOR
# bounds already reach LLVM's scalar evolution, and a declared subrange is
# not a trustworthy fact (RANGECK-). The relocation count is x86-64 specific.
# Whole-vector checks: a MATHCK+ integer VECTOR + - * or negation computes
# every lane with one vector overflow intrinsic and branches once on the OR
# of the overflow lanes; only the cold path redoes the operation lane by
# lane (its diagnostics are pinned by mathck_vector.sh). Fixtures in
# tests/fixtures/mathck:
#   fold.pas/.out       stdin 3; exact output at O0-O3, 9 failure calls in the
#                       O0 IR, 5 failure-call relocations in each O1-O3 object
#   fold_bound.err      fold.pas with its first loop ending at 32767 instead:
#                       the located trap on its last step, empty stdout
#   vector_shape.pas    {ELEM} = INTEGER8, INTEGER, WORD32, INTEGER64; -S -O0
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
emitted=9 # checked operations in fold.pas, all emitted at O0
kept=5    # three accumulations into k, n + 1 and s * n
declare -A expect=([fold]=4 [bound]=4 [vector]=4)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # output args...; never reuse a previous cell's output
  local out=$1; shift
  rm -f "$out"
  bin/pascal1981 "$@" -o "$out" || die "compile $* -o $out"
}

occurrences() { # fixed-string file
  grep -oF "$1" "$2" | wc -l || true
}

fold_unit() { # opt
  local opt=$1 status=0 n
  build "$dir/fold" -O"$opt" "$fixtures/fold.pas"
  timeout 10 "$dir/fold" <<< 3 > "$dir/stdout" 2> "$dir/stderr" || status=$?
  [ "$status" -eq 0 ] || die "fold O$opt: exit status $status"
  diff -u "$fixtures/fold.out" "$dir/stdout" || die "fold O$opt: stdout"
  [ ! -s "$dir/stderr" ] || die "fold O$opt: stderr not empty"
  if [ "$opt" = 0 ]; then
    build "$dir/fold.ll" -O0 -S "$fixtures/fold.pas"
    n=$(occurrences 'call void @pas_math_overflow' "$dir/fold.ll")
    [ "$n" -eq "$emitted" ] || die "fold O0 IR: $n failure calls, expected $emitted"
  else
    build "$dir/fold.o" -O"$opt" -c "$fixtures/fold.pas"
    objdump -dr "$dir/fold.o" > "$dir/dump" || die "objdump O$opt"
    n=$(grep -oE 'R_X86_64_PLT32[[:space:]]+pas_math_overflow' "$dir/dump" | wc -l || true)
    [ "$n" -eq "$kept" ] || die "fold O$opt: $n failure relocations, expected $kept"
  fi
  count fold
}

bound_unit() { # opt
  local opt=$1 status=0
  sed 's/FOR i := 1 TO 32766 DO/FOR i := 32760 TO 32767 DO/' "$fixtures/fold.pas" > "$dir/bound.pas"
  grep -qF 'FOR i := 32760 TO 32767 DO' "$dir/bound.pas" || die "bound: no loop to edit"
  build "$dir/bound" -O"$opt" "$dir/bound.pas"
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 10 "$dir/bound" <<< 3 > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "bound O$opt: did not fail"
  [ ! -s "$dir/stdout" ] || die "bound O$opt: stdout not empty"
  diff -u "$fixtures/fold_bound.err" "$dir/stderr" || die "bound O$opt: stderr"
  count bound
}

vector_unit() { # elem bits
  local elem=$1 bits=$2 sign=s op want n any anys
  [[ $elem == WORD* ]] && sign=u
  sed "s/{ELEM}/$elem/" "$fixtures/vector_shape.pas" > "$dir/vec.pas"
  build "$dir/vec.ll" --dialect extended -O0 -S "$dir/vec.pas"
  for op in add sub mul; do
    [ "$op" = sub ] && want=2 || want=1 # negation is 0 - v
    n=$(occurrences "call { <4 x i$bits>, <4 x i1> } @llvm.$sign$op.with.overflow.v4i$bits(" "$dir/vec.ll")
    [ "$n" -eq "$want" ] || die "$elem: $n $sign$op intrinsics, expected $want"
  done
  mapfile -t anys < <(grep -oE '%vmath\.any[0-9]* = call i1 @llvm\.vector\.reduce\.or\.v4i1\(' \
    "$dir/vec.ll" | cut -d' ' -f1)
  [ "${#anys[@]}" -eq 4 ] || die "$elem: ${#anys[@]} lane reductions, expected 4"
  for any in "${anys[@]}"; do
    grep -qE "br i1 ${any//./\\.}, label %vmath\.lanes[0-9]*, label %vmath\.ok[0-9]*" "$dir/vec.ll" ||
      die "$elem: no branch on $any"
  done
  # The lane-by-lane failure paths exist only behind those branches.
  n=$(occurrences 'call void @pas_math_overflow' "$dir/vec.ll")
  [ "$n" -eq 16 ] || die "$elem: $n failure calls, expected 16"
  count vector
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for opt in 0 1 2 3; do
  start "fold-O$opt" fold_unit "$opt"
  start "bound-O$opt" bound_unit "$opt"
done
start vector-INTEGER8 vector_unit INTEGER8 8
start vector-INTEGER vector_unit INTEGER 16
start vector-WORD32 vector_unit WORD32 32
start vector-INTEGER64 vector_unit INTEGER64 64
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
echo "PASS: MATHCK optimization: ${got[fold]} folding cells ($emitted checks emitted," \
  "$kept unprovable kept at O1-O3, exact output); ${got[bound]} FOR-to-maximum trap" \
  "cells; ${got[vector]} whole-vector check IR shapes (one overflow branch per" \
  "operation, lane-by-lane only on the cold path)"
