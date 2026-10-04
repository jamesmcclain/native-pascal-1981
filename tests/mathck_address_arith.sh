#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Address arithmetic and [C] values at MATHCK's boundary. Pointer/ADRMEM
# `+ offset` is an element-scaled (byte-scaled for ADRMEM) non-inbounds GEP:
# address arithmetic, not MATHCK, never trapping and never LLVM UB. The
# offset is widened by its own signedness, so a WORD offset of 40000
# addresses element 40000. Arithmetic *inside* an offset expression is
# ordinary MATHCK arithmetic at its own operators. Other pointer operators
# are typecheck errors, with no output. Arithmetic inside a [C] routine is
# outside MATHCK; a [C] result used in Pascal arithmetic is checked like any
# other value. Fixtures in tests/fixtures/mathck (the suite prepends MATHCK+
# or MATHCK- to the first two):
#   address_word_offset.pas/.out       WORD/ADRMEM offsets, O0-O3
#   address_c_value.pas                C abs(-2147483647) + 1 in Pascal, O0-O3;
#                                      _checked.out/.err trap, _unchecked.out
#                                      wraps (no header: line 8 is located)
#   address_gep.pas                    MATHCK+ -S -O0 IR shape; with its last
#                                      statement replaced by each rejected
#                                      operator, address_reject.err exactly
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
rejected=('q := p - 1' 'q := p * 2' 'q := p DIV 2' 'q := 2 - p' 'q := p + 1.5')
declare -A expect=([offset]=8 [cvalue]=8 [ir]=1 [reject]=5)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # opt source exe; never reuse a previous cell's binary
  rm -f "$3"
  bin/pascal1981 --dialect extended -O"$1" "$2" -o "$3" || die "compile $2 (O$1)"
}

run() { # exe; status in $status
  status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 10 "$1" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
}

run_unit() { # flag opt
  local flag=$1 opt=$2 tag status
  [ "$flag" = + ] && tag=checked || tag=unchecked
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/address_word_offset.pas" > "$dir/word.pas"
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/address_c_value.pas" > "$dir/cvalue.pas"
  build "$opt" "$dir/word.pas" "$dir/word"
  run "$dir/word"
  [ "$status" -eq 0 ] || die "offsets MATHCK$flag O$opt: exit status $status"
  diff -u "$fixtures/address_word_offset.out" "$dir/stdout" || die "offsets MATHCK$flag O$opt: stdout"
  [ ! -s "$dir/stderr" ] || die "offsets MATHCK$flag O$opt: stderr"
  count offset
  build "$opt" "$dir/cvalue.pas" "$dir/cvalue"
  run "$dir/cvalue"
  diff -u "$fixtures/address_c_value_$tag.out" "$dir/stdout" || die "[C] MATHCK$flag O$opt: stdout"
  if [ "$flag" = + ]; then
    [ "$status" -ne 0 ] || die "[C] MATHCK+ O$opt: did not fail"
    diff -u "$fixtures/address_c_value_checked.err" "$dir/stderr" || die "[C] MATHCK+ O$opt: stderr"
  else
    [ "$status" -eq 0 ] || die "[C] MATHCK- O$opt: exit status $status"
    [ ! -s "$dir/stderr" ] || die "[C] MATHCK- O$opt: stderr"
  fi
  count cvalue
}

occurrences() { # fixed-string file
  grep -oF "$1" "$2" | wc -l || true
}

ir_unit() {
  # Two GEPs with i64 offsets; only the offset expression's `-` is checked
  # (one overflow intrinsic), never the address step.
  local n
  rm -f "$dir/gep.ll"
  bin/pascal1981 --dialect extended -O0 -S "$fixtures/address_gep.pas" -o "$dir/gep.ll" ||
    die "compile address_gep.pas"
  n=$(occurrences 'getelementptr i16, ptr' "$dir/gep.ll")
  [ "$n" -eq 2 ] || die "IR: $n i16 GEPs, expected 2"
  ! grep -qF 'getelementptr inbounds' "$dir/gep.ll" || die "IR: inbounds GEP"
  n=$(occurrences 'call { i32, i1 } @llvm.ssub.with.overflow.i32' "$dir/gep.ll")
  [ "$n" -eq 1 ] || die "IR: $n checked subtractions, expected 1"
  ! grep -qF 'sadd.with.overflow' "$dir/gep.ll" || die "IR: checked address add"
  count ir
}

reject_unit() {
  local template statement
  template=$(< "$fixtures/address_gep.pas")
  [[ $template == *'q := p + (n - 1)'* ]] || die "address_gep.pas: no statement to replace"
  for statement in "${rejected[@]}"; do
    printf '%s\n' "${template//'q := p + (n - 1)'/"$statement"}" > "$dir/rej.pas"
    rm -f "$dir/rej.ll"
    ! bin/pascal1981 --dialect extended -O0 -S "$dir/rej.pas" -o "$dir/rej.ll" \
      2> "$dir/stderr" || die "$statement: accepted"
    diff -u "$fixtures/address_reject.err" "$dir/stderr" || die "$statement: stderr"
    [ ! -s "$dir/rej.ll" ] || die "$statement: IR written"
    count reject
  done
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
for opt in 0 1 2 3; do
  start "checked-O$opt" run_unit + "$opt"
  start "unchecked-O$opt" run_unit - "$opt"
done
start ir ir_unit
start reject reject_unit
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
echo "PASS: MATHCK address arithmetic boundary:" \
  "$(( got[offset] + got[cvalue] + got[ir] + got[reject] )) cells (WORD/ADRMEM GEP" \
  "offsets at O0-O3 under both settings, unchecked GEP with checked offset" \
  "expressions, [C] results checked in Pascal, non-+ pointer operators rejected)"
