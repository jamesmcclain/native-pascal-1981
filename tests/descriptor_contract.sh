#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Host descriptor transport ABI and unsupported-boundary contracts.
# Compile-only rejection/IR checks never link undefined foreign functions or
# execute invalid raw/DEVICE accesses. Runtime goldens use valid allocations.
set -euo pipefail
cd "$(dirname "$0")/.."
driver=${DESCRIPTOR_DRIVER:-bin/pascal1981-native}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
checks=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
require() {
  checks=$((checks + 1))
  if grep -Eq "$2" "$3"; then pass "$1"; else fail "$1"; fi
}
forbid() {
  checks=$((checks + 1))
  if grep -Eq "$2" "$3"; then fail "$1"; else pass "$1"; fi
}
diagnostic() {
  while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$work/compile.err"
}
compile_ir() {
  "$driver" --dialect extended "${@:3}" -S "$1" -o "$2" \
    >"$work/compile.out" 2>"$work/compile.err"
}

# The ordinary golden runner pins stdout, stderr and runtime status. Its driver
# is fixed, so a custom IR driver does not replace these native runtime checks.
checks=$((checks + 1))
if bash tests/run.sh -v tests/descriptor/transport.pas tests/descriptor/layout.pas \
    tests/descriptor/register_budget.pas tests/golden/descriptor_unsafe.pas \
    tests/golden/descriptor_word_domain.pas tests/golden/descriptor_ordinal_domains.pas \
    tests/golden/descriptor_unsafe_shadow.pas \
    tests/integration/descriptor_units.pas tests/dialect/vintage_unsafe_conversion.pas; then
  pass 'runtime whole-value propagation and layout'
else
  fail 'runtime whole-value propagation and layout'
fi

checks=$((checks + 1))
if compile_ir tests/descriptor/transport.pas "$work/transport.ll"; then
  pass 'transport fixture compiles'
  ir="$work/transport.ll"
  require 'descriptor global storage' '^@p = global \{ ptr, i64 \} zeroinitializer' "$ir"
  require 'descriptor record storage' '^@h = global \{ \{ ptr, i64 \} \} zeroinitializer' "$ir"
  require 'descriptor array storage' '^@a = global \[2 x \{ ptr, i64 \}\] zeroinitializer' "$ir"
  require 'whole descriptor load' 'load \{ ptr, i64 \}, ptr' "$ir"
  require 'whole descriptor alias store' 'store \{ ptr, i64 \} .*, ptr @alias' "$ir"
  require 'whole descriptor NEW publication' 'store \{ ptr, i64 \} .*, ptr @p' "$ir"
  require 'descriptor NIL publication' 'store \{ ptr, i64 \} zeroinitializer, ptr @resultptr' "$ir"
  require 'value pointer parameter ABI' '^define void @Observe\(i64 %[^,]+, i64 %[^)]+\)' "$ir"
  require 'VAR pointer parameter ABI' '^define void @Rebind\(ptr %[^,]+, i64 %[^,]+, i64 %[^)]+\)' "$ir"
  require 'pointer result ABI' '^define \{ i64, i64 \} @Echo\(i64 %[^,]+, i64 %[^)]+\)' "$ir"
  require 'record result ABI' '^define \{ i64, i64 \} @EchoHolder\(i64 %[^,]+, i64 %[^)]+\)' "$ir"
  require 'pointer result call ABI' 'call \{ i64, i64 \} @Echo\(i64 [^,]+, i64 [^)]+\)' "$ir"
  require 'VAR call transports upper' 'call void @Rebind\(ptr @resultptr, i64 [^,]+, i64 [^)]+\)' "$ir"
  forbid 'no pre-data header lookup/free' 'getelementptr.*i64 -8' "$ir"
else
  fail 'transport fixture compiles (not a descriptor assertion failure)'
  diagnostic
fi

checks=$((checks + 1))
if compile_ir tests/descriptor/aggregate_abi.pas "$work/aggregate.ll"; then
  pass 'aggregate fixture compiles'
  ir="$work/aggregate.ll"
  require '32-byte descriptor pair value ABI' '^define void @TakePair\(ptr byval\(\{ \{ ptr, i64 \}, \{ ptr, i64 \} \}\) align 8 %' "$ir"
  require '32-byte descriptor pair result ABI' '^define void @ReturnPair\(ptr noalias sret\(\{ \{ ptr, i64 \}, \{ ptr, i64 \} \}\) align 8 %' "$ir"
  require 'pair call uses byval' 'call void @TakePair\(ptr byval\(' "$ir"
  require 'pair result call uses sret' 'call void @ReturnPair\(ptr (noalias )?sret\(' "$ir"
else
  fail 'aggregate fixture compiles (not a descriptor assertion failure)'
  diagnostic
fi

checks=$((checks + 1))
if compile_ir tests/descriptor/register_budget.pas "$work/budget.ll"; then
  pass 'register budget fixture compiles'
  require 'descriptor rolls back after five GP arguments' '^define .*@Spill\(i32 .*ptr byval\(\{ ptr, i64 \}\) align 8' "$work/budget.ll"
  require 'sret hidden pointer consumes a GP register' '^define void @SpillSret\(ptr noalias sret\(.*ptr byval\(\{ ptr, i64 \}\) align 8' "$work/budget.ll"
else fail 'register budget fixture compiles'; diagnostic; fi

checks=$((checks + 1))
if compile_ir tests/golden/descriptor_unsafe.pas "$work/unsafe.ll"; then
  pass 'explicit unsafe conversion fixture compiles'
  checks=$((checks + 1))
  if [ "$(grep -c '^warning: unsafe-super-array-conversion$' "$work/compile.err")" -eq 8 ]; then
    pass 'both unsafe intrinsics issue stable warnings'
  else fail 'both unsafe intrinsics issue stable warnings'; diagnostic; fi
  require 'unsafe import validates before construction' 'call void @pas_super_import_check\(' "$work/unsafe.ll"
  forbid 'unsafe import/export never reads a pre-data header' 'getelementptr.*i64 -8' "$work/unsafe.ll"
else fail 'explicit unsafe conversion fixture compiles'; diagnostic; fi

checks=$((checks + 1))
if compile_ir tests/golden/descriptor_unsafe_shadow.pas "$work/shadow.ll" && [ ! -s "$work/compile.err" ]; then
  pass 'unsafe intrinsic user shadowing emits no warnings'
else fail 'unsafe intrinsic user shadowing emits no warnings'; diagnostic; fi

checks=$((checks + 1))
ulimit -c 0
if "$driver" --dialect extended tests/descriptor/unsafe_failures.pas -o "$work/unsafe-bad" >"$work/compile.out" 2>"$work/compile.err"; then
  pass 'unsafe failure fixture compiles'
  reasons=('lower bound does not match declared lower' 'upper bound is outside declared index domain'
           'requires non-NIL data' 'data is not correctly aligned'
           'upper bound is outside declared index domain' 'upper bound is outside declared index domain')
  for mode in 1 2 3 4 5 6; do
    checks=$((checks + 1)); code=0
    { printf '%s\n' "$mode" | "$work/unsafe-bad" >"$work/actual.out" 2>"$work/actual.err"; } 2>/dev/null || code=$?
    printf 'runtime error: UNSAFESUPER %s\n' "${reasons[mode - 1]}" >"$work/expected.err"
    if [ "$code" -eq 134 ] && [ ! -s "$work/actual.out" ] && cmp -s "$work/expected.err" "$work/actual.err"; then
      pass "unsafe import failure $mode under INDEXCK-"
    else fail "unsafe import failure $mode under INDEXCK-"; fi
  done
else fail 'unsafe failure fixture compiles'; diagnostic; fi

checks=$((checks + 1))
if "${CC:-clang}" -Wall -Wextra -o "$work/import-runtime" tests/super_import_runtime.c runtime/build/libpascalrt.a && "$work/import-runtime"; then
  pass 'unsafe import runtime span/address overflow checks'
else fail 'unsafe import runtime span/address overflow checks'; fi

# DEVICE itself is not migrated. Protect its thin ABI in both execution modes.
for backend in host nvptx; do
  flags=()
  if [ "$backend" = nvptx ]; then flags=(--device-triple nvptx64-nvidia-cuda); fi
  checks=$((checks + 1))
  ir="$work/device-$backend.ll"
  if compile_ir tests/descriptor/device_thin.pas "$ir" "${flags[@]}"; then
    pass "DEVICE $backend fixture compiles"
    require "DEVICE $backend retains thin parameter" '^define (ptx_kernel )?void @touch\(ptr (align 4 )?%' "$ir"
    forbid "DEVICE $backend excludes host descriptor" '\{ ptr, i64 \}' "$ir"
  else
    fail "DEVICE $backend fixture compiles"
    diagnostic
  fi
done

checks=$((checks + 1))
if compile_ir tests/descriptor/device_interface_thin.pas "$work/device-interface.ll"; then
  pass 'spliced DEVICE interface compiles in host'
  require 'DEVICE interface pointer storage stays thin after host restoration' '^@raw = global ptr null' "$work/device-interface.ll"
  require 'DEVICE interface kernel signature stays thin' '^declare void @touch\(ptr\)' "$work/device-interface.ll"
else fail 'spliced DEVICE interface compiles in host'; diagnostic; fi

checks=$((checks + 1))
if compile_ir tests/descriptor/foreign_recursive_thin.pas "$work/recursive-thin.ll"; then
  pass 'recursive thin pointer C signature remains supported'
  require 'recursive thin pointer C signature is one pointer' '^declare void @Sink\(ptr\)' "$work/recursive-thin.ll"
else fail 'recursive thin pointer C signature remains supported'; diagnostic; fi

checks=$((checks + 1))
if compile_ir tests/descriptor/device_host_raw_interface.pas "$work/device-host-raw.ll"; then
  pass 'opaque host raw API remains usable in CPU DEVICE compilation'
  require 'host raw API retains pointer result ABI' '^declare ptr @RawData\(\)' "$work/device-host-raw.ll"
else fail 'opaque host raw API remains usable in CPU DEVICE compilation'; diagnostic; fi

for src in tests/descriptor/reject_*.pas; do
  checks=$((checks + 1))
  name=$(basename "$src" .pas)
  if compile_ir "$src" "$work/$name.ll"; then
    fail "$name: unsupported descriptor boundary accepted"
  # A real typecheck rejection can also produce a downstream "Failed to parse
  # input AST JSON" message. Do not confuse that with the primary diagnostic.
  elif grep -Eiq 'parser error|undefined variable|not a function|unknown.*kernel' "$work/compile.err"; then
    fail "$name: unrelated frontend failure"
    diagnostic
  # An element layout too large for INTEGER32 bookkeeping is rejected where
  # its size is first needed (the RECORD declaration), before SUPER NEW.
  elif grep -Eiq 'super.?array|descriptor|pointer|\[C\]|foreign|ADRMEM|CPTR|device|LAUNCH|DEVCOPY|ADR|layout exceeds' "$work/compile.err"; then
    pass "$name: descriptor boundary rejected"
  else
    fail "$name: rejection lacks a boundary diagnostic"
    diagnostic
  fi
done

echo "Descriptor contract: $failures failed check(s) / $checks checks"
[ "$failures" -eq 0 ]
