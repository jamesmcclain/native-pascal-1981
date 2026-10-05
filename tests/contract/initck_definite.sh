#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Compile-time proofs at O0, plus success/failure parity at every driver level.
printf '%s\n' -32767 0 1 A > "$work/expected"
for dialect in vintage extended; do
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" \
      tests/contract/fixtures/initck_definite_ok.pas -o "$work/ok"
    "$work/ok" > "$work/out" 2> "$work/err"
    diff -u "$work/expected" "$work/out"
    test ! -s "$work/err"
    for fixture in initck_definite_fail initck_definite_fail_goto_skip \
        initck_definite_fail_zero_loop initck_definite_fail_unchecked_copy \
        initck_definite_fail_call_effect; do
      cp "tests/contract/fixtures/$fixture.pas" "$work/fail.pas"
      # Preserve the former generator's extra print newline.
      printf '\n' >> "$work/fail.pas"
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/fail.pas" -o "$work/fail"
      status=0
      { "$work/fail" > "$work/out" 2> "$work/err"; } 2>/dev/null || status=$?
      test "$status" -ne 0
      test "$(<"$work/out")" = prefix
      test "$(wc -l < "$work/err")" -eq 1
      grep -Eq '^runtime error: INITCK uninitialized local x at line [0-9]+ column [0-9]+$' "$work/err"
      # Disabled bad paths are compile-only, never executed.
      # Keep the extra trailing newline emitted by the former Python print.
      {
        sed 's/{$INITCK+}/{$INITCK-}/g' "$work/fail.pas"
        printf '\n'
      } > "$work/off.pas"
      bin/pascal1981 --dialect "$dialect" -O"$opt" -S "$work/off.pas" -o "$work/off.ll"
      ! grep -Eq 'call void @pas_initck_(error|fail)' "$work/off.ll"
    done
  done
  bin/pascal1981 --dialect "$dialect" -O0 -S \
    tests/contract/fixtures/initck_definite_ok.pas -o "$work/on.ll"
  bin/pascal1981 --dialect "$dialect" -O0 -S \
    tests/contract/fixtures/initck_definite_fail.pas -o "$work/fail.ll"
  python3 tests/contract/fixtures/initck_definite/proven-reads.py "$work/on.ll" "$work/fail.ll"
done
echo 'PASS: INITCK definite initialization, conservative barriers, O0 proofs and O0/O1/O2/O3 behavior'
