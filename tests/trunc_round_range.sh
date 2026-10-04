#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# TRUNC/ROUND INTEGER range check (G26): always on, independent of MATHCK.
# IBM 11-6: "Error if ABS(X) > MAXINT". A result outside -32768..32767, or a
# NaN argument, fails with one located `runtime error:` line after flushing
# stdout, under {$MATHCK+} and {$MATHCK-} alike (prepended), both dialects,
# O0-O3. Fixtures under tests/fixtures/mathck:
#   trunc_round_valid.pas/.out      results that fit, including the extremes
#                                   and ROUND's half-away-from-zero ties
#   trunc_round_invalid.pas/.cases  template + one out-of-range call per row
#                                   with its exact diagnostic
#   trunc_round_real32.pas/.err     a REAL32 argument widens first and is
#                                   checked the same way (extended)
#   trunc_round_device/             CPU DEVICE code takes the host failure
#                                   path; NVPTX has no host failure path and
#                                   saturates (llvm.fptosi.sat), never poison
#   trunc_round_ir.pas              the range test precedes the conversion:
#                                   fptosi only in conv.ok blocks
# Runtime failure is checked as nonzero, not an exact status.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
declare -A expect=([valid]=16 [invalid]=128 [real32]=8 [device]=4 [nvptx]=2 [ir]=1)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

build() { # dialect opt source exe; never reuse a previous cell's binary
  rm -f "$4"
  bin/pascal1981 --dialect "$1" -O"$2" "$3" -o "$4" ||
    die "compile $3 ($1, O$2)"
}

expect_fail() { # label exe expected-stderr-file: prefix, then the diagnostic
  local status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 5 "$2" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "$1: did not fail"
  printf 'prefix\n' | diff -u - "$dir/stdout" || die "$1: stdout"
  diff -u "$3" "$dir/stderr" || die "$1: stderr"
}

valid_unit() { # dialect flag: fitting results, and REAL32 failure (extended)
  local dialect=$1 flag=$2 opt status
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/trunc_round_valid.pas" > "$dir/valid.pas"
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/trunc_round_real32.pas" > "$dir/real32.pas"
  for opt in 0 1 2 3; do
    build "$dialect" "$opt" "$dir/valid.pas" "$dir/valid"
    status=0
    timeout 5 "$dir/valid" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "valid $dialect MATHCK$flag O$opt: exit status $status"
    diff -u "$fixtures/trunc_round_valid.out" "$dir/stdout" ||
      die "valid $dialect MATHCK$flag O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "valid $dialect MATHCK$flag O$opt: stderr"
    count valid
    [ "$dialect" = extended ] || continue
    build "$dialect" "$opt" "$dir/real32.pas" "$dir/real32"
    expect_fail "REAL32 MATHCK$flag O$opt" "$dir/real32" "$fixtures/trunc_round_real32.err"
    count real32
  done
}

invalid_unit() { # dialect row-number
  local dialect=$1 row=$2 call expected source flag opt
  IFS='|' read -r call expected < <(grep -v '^#' "$fixtures/trunc_round_invalid.cases" |
    sed -n "${row}p")
  [ -n "$call" ] && [ -n "$expected" ] || die "row $row missing"
  printf '%s\n' "$expected" > "$dir/expected"
  source=$(< "$fixtures/trunc_round_invalid.pas")
  source=${source//'{CALL}'/$call}
  for flag in + -; do
    printf '{$MATHCK%s}\n%s\n' "$flag" "$source" > "$dir/bad.pas"
    [ "$(sed -n 7p "$dir/bad.pas")" = "  i := $call; WRITELN(i)" ] || die "line 7: $call"
    for opt in 0 1 2 3; do
      build "$dialect" "$opt" "$dir/bad.pas" "$dir/bad"
      expect_fail "$call $dialect MATHCK$flag O$opt" "$dir/bad" "$dir/expected"
      count invalid
    done
  done
}

device_unit() {
  local value expected opt sat
  cp "$fixtures"/trunc_round_device/conv.{inc,impl} "$dir/"
  for value in 1234.6 100000.0; do
    sed "s/{VALUE}/$value/" "$fixtures/trunc_round_device/main.pas" > "$dir/main.pas"
    for opt in 0 2; do
      rm -f "$dir/devhost"
      (cd "$dir" && "$root/bin/pascal1981" --dialect extended -O"$opt" \
         main.pas conv.impl -o devhost) || die "compile DEVICE host $value O$opt"
      if [ "$value" = 1234.6 ]; then
        status=0
        timeout 5 "$dir/devhost" > "$dir/stdout" 2> "$dir/stderr" || status=$?
        [ "$status" -eq 0 ] || die "DEVICE $value O$opt: exit status $status"
        diff -u "$fixtures/trunc_round_device/ok.out" "$dir/stdout" ||
          die "DEVICE $value O$opt: stdout"
        [ ! -s "$dir/stderr" ] || die "DEVICE $value O$opt: stderr"
      else
        expect_fail "DEVICE $value O$opt" "$dir/devhost" "$fixtures/trunc_round_device/fail.err"
      fi
      count device
    done
  done
  for opt in 0 2; do
    rm -f "$dir/nvptx.ll"
    (cd "$dir" && "$root/bin/pascal1981" --dialect extended -O"$opt" \
       --device-triple nvptx64-nvidia-cuda -S conv.impl -o nvptx.ll) ||
      die "compile NVPTX O$opt"
    sat=$(grep -oF 'call i16 @llvm.fptosi.sat.i16.f64' "$dir/nvptx.ll" | wc -l || true)
    [ "$sat" -eq 2 ] || die "NVPTX O$opt: $sat saturating conversions"
    ! grep -qF 'fptosi double' "$dir/nvptx.ll" || die "NVPTX O$opt: fptosi double"
    ! grep -qF pas_conversion_error "$dir/nvptx.ll" || die "NVPTX O$opt: host failure call"
    count nvptx
  done
}

ir_unit() { # every fptosi double sits in a conv.ok* block
  local found calls
  rm -f "$dir/ir.ll"
  bin/pascal1981 -O0 -S "$fixtures/trunc_round_ir.pas" -o "$dir/ir.ll" ||
    die "compile -S trunc_round_ir.pas"
  calls=$(grep -oF 'call void @pas_conversion_error' "$dir/ir.ll" | wc -l || true)
  [ "$calls" -eq 2 ] || die "IR: $calls failure calls"
  found=$(awk '
    { head = $0; sub(/;.*/, "", head); sub(/[ \t]+$/, "", head) }
    head != "" && head !~ /^[ \t]/ && head ~ /:$/ { label = head; next }
    index($0, "fptosi double") {
      if (label !~ /^conv\.ok/) { print "unguarded: " $0 > "/dev/stderr"; exit 1 }
      found++
    }
    END { print found + 0 }' "$dir/ir.ll") || die "IR: fptosi outside conv.ok"
  [ "$found" -eq 2 ] || die "IR: $found conversions"
  count ir
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
rows=$(grep -vc '^#' "$fixtures/trunc_round_invalid.cases")
[ "$rows" -eq 8 ] || die "$rows invalid rows, expected 8"
for dialect in vintage extended; do
  for flag in + -; do
    start "valid-$dialect$flag" valid_unit "$dialect" "$flag"
  done
  for row in $(seq "$rows"); do
    start "invalid-$dialect-$row" invalid_unit "$dialect" "$row"
  done
done
start device device_unit
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
echo "PASS: TRUNC/ROUND INTEGER range: $(( got[valid] + got[invalid] + got[real32] ))" \
  "runtime cells (${got[valid]} fit, ${got[invalid]} out of range, ${got[real32]} REAL32;" \
  "both dialects, MATHCK+ and MATHCK-, O0-O3); range test before fptosi in IR;" \
  "$(( got[device] + got[nvptx] )) DEVICE cells (CPU host failure, NVPTX saturates)"
