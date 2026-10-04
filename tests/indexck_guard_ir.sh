#!/usr/bin/env bash
# Compile only: the disabled selector is deliberately out of bounds.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_guard_ir.pas -o "$work/guard.ll"
# Four checked selectors (including dead a[0] and both restored flags inside
# expression-bearing statements), two unchecked selectors inside expressions,
# plus unchecked constant a[3]. Never execute the unchecked out-of-range store.
[ "$(grep -Ec '^index\.bad[0-9]*:' "$work/guard.ll")" -eq 4 ]
[ "$(grep -Ec '^index\.ok[0-9]*:' "$work/guard.ll")" -eq 4 ]
[ "$(grep -c 'call void @pas_array_index_error(' "$work/guard.ll")" -eq 4 ]
! grep -q 'call void @abort()' "$work/guard.ll"
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
# Compile-only exclusion probes: STRING/LSTRING indexes and VECTOR lanes
# (plus variable VLOAD/VSTORE) do not gain fixed-array host diagnostic calls.
# SUPER ARRAY subscripts are now descriptor-guarded (probe below).
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_exclusions_ir.pas -o "$work/exclusions.ll"
! grep -q 'pas_array_index_error' "$work/exclusions.ll"
# Descriptor-backed SUPER ARRAY subscripts compare the widened index against
# the selected descriptor's actual upper (sext of the extracted i64) before
# the GEP, and report through the same host diagnostic.
bin/pascal1981 --dialect extended -S tests/golden/indexck_super_endpoints.pas -o "$work/super.ll"
grep -Eq 'icmp sge i128 .*-2' "$work/super.ll"
grep -Eq 'sext i64 .* to i128' "$work/super.ll"
grep -Eq 'icmp sle i128' "$work/super.ll"
grep -q 'call void @pas_array_index_error(' "$work/super.ll"
# The descriptor data pointer is never dereferenced by the guard itself.
! grep -Eq 'getelementptr.*index\.bad' "$work/super.ll"
# Snapshot behavior and guard-free IR for disabled checks: seven super-array
# subscripts, three checked (one dead) and four unchecked. Never executed.
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_super_guard_ir.pas -o "$work/super-snaps.ll"
[ "$(grep -Ec '^index\.nil[0-9]*:' "$work/super-snaps.ll")" -eq 3 ]
[ "$(grep -Ec '^index\.nilk[0-9]*:' "$work/super-snaps.ll")" -eq 3 ]
[ "$(grep -Ec '^index\.bad[0-9]*:' "$work/super-snaps.ll")" -eq 3 ]
[ "$(grep -Ec '^index\.ok[0-9]*:' "$work/super-snaps.ll")" -eq 3 ]
[ "$(grep -c 'call void @pas_super_index_nil_error()' "$work/super-snaps.ll")" -eq 3 ]
[ "$(grep -c 'call void @pas_array_index_error(' "$work/super-snaps.ll")" -eq 3 ]
# No data access inside a NIL-failure block: only the diagnostic call and
# the unreachable terminator appear between the label and the next block.
! awk '/^index\.nil[0-9]*:/{inbad=1;next} /^$/{inbad=0} inbad && /getelementptr|load |store /{found=1} END{exit found}' "$work/super-snaps.ll"
# A deterministic NIL failure is a runtime diagnostic, not a raw null GEP:
# the checked selector's GEP only follows the index.ok continuation.
grep -q 'call void @pas_super_index_nil_error()' "$work/super-snaps.ll"
# DEVICE code, even when lowered for the host, must not reference host INDEXCK.
bin/pascal1981 --dialect extended -S tests/fixtures/indexck_device.pas -o "$work/device-host.ll"
! grep -q 'pas_array_index_error' "$work/device-host.ll"
bin/pascal1981 --dialect extended --device-triple nvptx64-nvidia-cuda -S \
  tests/fixtures/indexck_device.pas -o "$work/device-nvptx.ll"
! grep -q 'pas_array_index_error' "$work/device-nvptx.ll"
echo 'PASS: fixed-array and descriptor-backed INDEXCK guards only enabled host selectors; preserve ordinal width and exclusions'
