#!/usr/bin/env bash
# Compile only: the disabled selector is deliberately out of bounds.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_guard_ir.pas -o "$work/guard.ll"
# Two checked selectors (including dead a[0]), one unchecked constant a[3].
# A bad constant is compiled, not rejected, and its guard runs only if reached.
[ "$(grep -Ec '^index\.bad[0-9]*:' "$work/guard.ll")" -eq 2 ]
[ "$(grep -Ec '^index\.ok[0-9]*:' "$work/guard.ll")" -eq 2 ]
[ "$(grep -c 'call void @abort()' "$work/guard.ll")" -eq 2 ]
grep -Eq 'br i1 false, label %index\.ok[0-9]*, label %index\.bad[0-9]*' "$work/guard.ll"
# Compare full-width typed values before computing a signed GEP offset.
bin/pascal1981 --dialect extended -S tests/golden/indexck_wide_ordinals.pas -o "$work/width.ll"
for pattern in 'sext i64 .* to i128' 'sext i8 .* to i128' \
               'zext i8 .* to i128' 'zext i16 .* to i128' \
               'zext i1 .* to i128' 'zext i32 .* to i128' \
               'icmp sge i128 .* 32768' 'icmp sge i128 .* 200' \
               'sub i64 .* 32768'; do
  grep -Eq "$pattern" "$work/width.ll"
done
bin/pascal1981 --dialect extended -S tests/golden/indexck_word64_bad.pas -o "$work/word64.ll"
grep -Eq 'zext i64 .* to i128' "$work/word64.ll"
bin/pascal1981 --dialect extended -S tests/golden/indexck_int64_bad.pas -o "$work/int64.ll"
grep -Eq 'sext i64 .* to i128' "$work/int64.ll"
echo 'PASS: fixed-array INDEXCK guards only enabled selectors and preserve ordinal width'
