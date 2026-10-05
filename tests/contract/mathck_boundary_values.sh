#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# Legitimate boundary values never trap under MATHCK+.
# tests/contract/fixtures/mathck/boundary_values.pas computes 32767, -32768, 0 and
# 65535 through every checked 16-bit operation, the listed edge cases from
# variables, and the same values as folded constants (derivations in the
# fixture header). -32768 is ordinary data, so it must be produced and
# consumed without a trap. Both dialects, O0-O3, both settings (prepended),
# exact boundary_values.out. At O0 the MATHCK+ IR must check every variable
# operation (one pas_math_overflow failure call each); MATHCK- has no overflow
# checks, only the mandatory zero-divisor failures, which both keep.
fixture=tests/contract/fixtures/mathck/boundary_values
overflow_sites=44 zero_sites=12
declare -A expect=([run]=16 [ir]=2)

sites() { grep -oF "call void @$1" "$2" | wc -l || true; } # zero matches is 0

setting_unit() { # flag dialect: four runtime cells; vintage also checks the O0 IR
  local flag=$1 dialect=$2 opt status calls
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixture".pas > "$dir/bv.pas"
  for opt in 0 1 2 3; do
    rm -f "$dir/bv"
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$dir/bv.pas" -o "$dir/bv" ||
      die "compile ($dialect MATHCK$flag O$opt)"
    status=0
    timeout 5 "$dir/bv" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "$dialect MATHCK$flag O$opt: exit status $status"
    diff -u "$fixture".out "$dir/stdout" || die "$dialect MATHCK$flag O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "$dialect MATHCK$flag O$opt: stderr not empty"
    count run
  done
  [ "$dialect" = vintage ] || return 0
  rm -f "$dir/bv.ll"
  bin/pascal1981 --dialect vintage -O0 -S "$dir/bv.pas" -o "$dir/bv.ll" ||
    die "compile -S (MATHCK$flag)"
  calls=$(sites pas_math_zero "$dir/bv.ll")
  [ "$calls" -eq "$zero_sites" ] || die "MATHCK$flag: $calls zero-divisor calls"
  calls=$(sites pas_math_overflow "$dir/bv.ll")
  if [ "$flag" = + ]; then
    [ "$calls" -eq "$overflow_sites" ] || die "MATHCK+: $calls overflow calls"
  else
    [ "$calls" -eq 0 ] || die "MATHCK-: $calls overflow calls"
    ! grep -qF .with.overflow "$dir/bv.ll" || die "MATHCK-: overflow intrinsic"
  fi
  count ir
}

for flag in + -; do
  for dialect in vintage extended; do
    unit "MATHCK$flag-$dialect" setting_unit "$flag" "$dialect"
  done
done
units_wait
echo "PASS: MATHCK boundary values: ${got[run]} cells (32767, -32768, 0, 65535" \
  "and the listed edge results from variables and constants never trap;" \
  "vintage/extended, O0-O3, both settings); O0 IR checks all $overflow_sites" \
  "variable operations under MATHCK+ and none under MATHCK-"
