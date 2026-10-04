#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INITCK release gate: checked success and failure, values, ABI.
#
# Release-gate fixtures: checked success/failure, non-sentinel values,
# partial aggregates/aliases/calls across flag regions, and compile-only
# disabled twins for uninitialized reads.
for kind in ok fail values mixed_ok mixed_fail; do
  cp "tests/contract/fixtures/initck_validation_$kind.pas" "$work/$kind-on.pas"
  # Keep the extra trailing newline emitted by the former Python print.
  {
    sed 's/{$INITCK+}/{$INITCK-}/g' "$work/$kind-on.pas"
    printf '\n'
  } > "$work/$kind-off.pas"
done
printf '0\n-32768\n' > "$work/ok.out"
printf '0:-32768:0:0:1\n0:-32768:0:0:1\n0:-32768\n0\n-32768\n0:-32768\n' > "$work/values.out"
printf '0\n2\n0\n3\n-32768\n-32766\n-32768\n-32765\n' > "$work/mixed_ok.out"
printf 'prefix\n7\n' > "$work/mixed_fail.out"
printf 'runtime error: INITCK uninitialized component p.y at line 6 column 22\n' > "$work/mixed_fail.err"
printf 'prefix\n' > "$work/fail.out"
printf 'runtime error: INITCK uninitialized local unset at line 8 column 21\n' > "$work/fail.err"
for dialect in vintage extended; do
  for opt in 0 1 2 3; do
    for kind in ok fail values mixed_ok mixed_fail; do
      for mode in on off; do
        # Disabled failure twins are ONLY compiled to IR, never linked or run.
        bin/pascal1981 --dialect "$dialect" -O"$opt" -S \
          "$work/$kind-$mode.pas" -o "$work/$kind-$mode.ll" 2> "$work/err"
        test ! -s "$work/err"
        if [ "$mode" = off ]; then
          ! grep -Eq 'call void @pas_initck_(error|fail)' "$work/$kind-$mode.ll"
        fi
        if [[ "$kind" = *fail && "$mode" = off ]]; then continue; fi
        bin/pascal1981 --dialect "$dialect" -O"$opt" \
          "$work/$kind-$mode.pas" -o "$work/run" 2> "$work/err"
        test ! -s "$work/err"
        status=0
        { "$work/run" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
        diff -u "$work/$kind.out" "$work/actual"
        if [[ "$kind" != *fail ]]; then
          test "$status" -eq 0
          test ! -s "$work/err"
        else
          test "$status" -ne 0
          diff -u "$work/$kind.err" "$work/err"
        fi
      done
    done
    if [ "$opt" = 0 ]; then
      python3 tests/contract/fixtures/initck_validation/value-actual-reads.py "$work/fail-on.ll" "$work/fail-off.ll"
      python3 tests/contract/fixtures/initck_validation/guarded-reads.py "$work/values-on.ll" "$work/values-off.ll"
    fi
  done
done
echo 'PASS: INITCK release fixtures, values, partial aggregates, aliases, mixed flags, calls, enabled/disabled IR (O0/O1/O2/O3)'
