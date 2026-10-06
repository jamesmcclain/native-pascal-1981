#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Unchecked CHR folding has the same low-eight-bit value as runtime conversion.
require bin/pascal1981 bin/codegen
for dialect in vintage extended; do
  specs=('-257 255' '-256 0' '-1 255' '0 0' '1 1' '255 255' '256 0' '300 44' '65535 255')
  if [[ $dialect == extended ]]; then
    specs+=('65536 0' '5000000000 0' '-9223372036854775807 1' '9223372036854775807 255')
    kind=INTEGER64
  else
    kind=INTEGER
  fi
  for spec in "${specs[@]}"; do
    read -r value ordinal <<< "$spec"
    # Vintage dynamic INTEGER cannot represent positive WORD values. The
    # literal twin still covers those; WORD stores the same positive value.
    actual_kind=$kind
    if [[ $dialect == vintage && $value == 65535 ]]; then actual_kind=WORD; fi
    printf '%s\n' "PROGRAM twin; VAR x: $actual_kind;" 'BEGIN' \
      "  x := $value;" '  {$RANGECK-}' \
      "  WRITELN(ORD(CHR($value)) + 1);" '  WRITELN(ORD(CHR(x)) + 1)' 'END.' > "$work/twin.pas"
    printf '%s\n%s\n' "$((ordinal + 1))" "$((ordinal + 1))" > "$work/expected"
    for opt in 0 1 2 3; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/twin.pas" -o "$work/twin"
      "$work/twin" > "$work/output" 2> "$work/error"
      diff -u "$work/expected" "$work/output" || die "$dialect $value O$opt constant/runtime mismatch"
      [[ ! -s $work/error ]] || die "$dialect $value O$opt stderr"
      pass "$dialect $value O$opt constant/runtime twin"
    done
  done
  # A CHAR label must be its represented value, not the unconverted integer.
  printf '%s\n' 'PROGRAM labels;' 'BEGIN' \
    '  {$RANGECK-} CASE CHR(44) OF CHR(300): WRITELN('\''match'\''); OTHERWISE WRITELN('\''wrong'\'') END' \
    'END.' > "$work/labels.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/labels.pas" -o "$work/labels"
    "$work/labels" > "$work/output"
    printf 'match\n' > "$work/expected"
    diff -u "$work/expected" "$work/output"
    pass "$dialect converted CASE label O$opt"
  done
done
# MIN64 is constructed from admitted literals: neither folder may negate it.
printf '%s\n' 'PROGRAM minimum; VAR x: INTEGER64;' 'BEGIN' \
  '  x := -9223372036854775807 - 1;' '  {$RANGECK-}' \
  '  WRITELN(ORD(CHR(-9223372036854775807 - 1)) + 1);' \
  '  WRITELN(ORD(CHR(x)) + 1)' 'END.' > "$work/minimum.pas"
printf '1\n1\n' > "$work/expected"
for opt in 0 1 2 3; do
  bin/pascal1981 --dialect extended -O"$opt" "$work/minimum.pas" -o "$work/minimum"
  "$work/minimum" > "$work/output"
  diff -u "$work/expected" "$work/output"
  pass "MIN64 constant/runtime twin O$opt"
done
# CONST values must feed ORD arithmetic and bounds as converted ordinals.
printf '%s\n' 'PROGRAM bounds;' '{$RANGECK-}' 'CONST C = CHR(300); N = ORD(CHR(300));' \
  'TYPE Arr = ARRAY [0..N] OF INTEGER;' 'VAR a: Arr;' \
  'BEGIN WRITELN(ORD(C) + 1); WRITELN(N); WRITELN(UPPER(a)) END.' > "$work/bounds.pas"
printf '45\n44\n44\n' > "$work/expected"
for opt in 0 1 2 3; do
  bin/pascal1981 --dialect extended -O"$opt" "$work/bounds.pas" -o "$work/bounds"
  "$work/bounds" > "$work/output"
  diff -u "$work/expected" "$work/output" || die "CONST/bounds O$opt"
  pass "CONST/bounds O$opt"
done
# Enabled domain checks must not be folded away into a valid character.
printf '%s\n' 'PROGRAM bad;' 'BEGIN WRITELN(ORD(CHR(300)) + 1) END.' > "$work/bad.pas"
if bin/pascal1981 "$work/bad.pas" -o "$work/bad" > "$work/output" 2> "$work/error"; then
  die 'enabled bad folded CHR admitted'
fi
grep -qF 'RANGECK constant CHR argument outside 0..255' "$work/error" || die 'enabled CHR diagnostic changed'
pass 'enabled CHR domain failure preserved'
finish 'CHR constant folding'
