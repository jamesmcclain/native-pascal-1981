#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Scalar WORD arithmetic against native arithmetic oracles.
#
# Native arithmetic oracles, not differential Python-reference comparisons.
# All divisors are nonzero; zero and signed MIN/-1 safety are separate gates.
fixtures=tests/contract/fixtures/mathck
for dialect in vintage extended; do
  names=(word_scalar)
  if [[ $dialect == extended ]]; then names+=(word_scalar_wide); fi
  for name in "${names[@]}"; do
    for flag in + -; do
      printf '{$MATHCK%s}\n' "$flag" > "$work/source.pas"
      cat "$fixtures/$name.pas" >> "$work/source.pas"
      for opt in 0 1 2 3; do
        rm -f "$work/probe" # never rerun a previous cell's binary
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/source.pas" -o "$work/probe"
        timeout 5 "$work/probe" > "$work/stdout" 2> "$work/stderr"
        diff -u "$fixtures/$name.out" "$work/stdout"
        test ! -s "$work/stderr"
      done
    done
  done
  # WORD membership in an INTEGER-based set (NEW-39): WORD 40000 is outside
  # 0..255 so IN evaluates to FALSE (zero-extended, not sign-extended).
  rm -f "$work/word_in"
  bin/pascal1981 --dialect "$dialect" "$fixtures/word_membership_reject.pas" -o "$work/word_in"
  timeout 5 "$work/word_in" > "$work/word_in.out" 2> "$work/word_in.err"
  test ! -s "$work/word_in.err"
  test "$(cat "$work/word_in.out")" = "FALSE"
  bin/pascal1981 --dialect "$dialect" -O0 -S "$fixtures/word_membership_reject.pas" -o "$work/word_in.ll"
  grep -Eq 'zext i16 .* to i64' "$work/word_in.ll"
  # A WORD set is rejected at its declaration: a set base's ordinals must
  # be in 0..255 (IBM manual 6-24), so WORD membership never arises.
  if bin/pascal1981 --dialect "$dialect" -S "$fixtures/word_set_membership_reject.pas" \
       -o "$work/word-set.ll" > "$work/reject.out" 2> "$work/reject.err"; then
    echo 'SET OF WORD was accepted; update audit coverage' >&2; exit 1
  fi
  grep -q 'SET base type ordinals 0..65535 are outside 0..255' "$work/reject.err"
done
# At O0 use variable operands so LLVM cannot constant-fold the instructions.
for name in word_scalar word_scalar_wide; do
  bin/pascal1981 --dialect extended -O0 -S "$fixtures/$name.pas" -o "$work/$name.ll"
done
for width in 8 16 32 64; do
  ir="$work/word_scalar_wide.ll"
  if [[ $width == 16 ]]; then ir="$work/word_scalar.ll"; fi
  for op in udiv urem sdiv srem; do
    grep -Eq "= $op i$width " "$ir"
  done
  for predicate in ult ule ugt uge eq ne slt; do
    grep -Eq "icmp $predicate i$width " "$ir"
  done
done
grep -Eq 'zext i8 .* to i32' "$work/word_scalar_wide.ll"
# WORD-family values convert to REAL unsigned (FLOAT, mixed operands).
grep -Eq 'uitofp i16 ' "$work/word_scalar.ll"
for width in 8 32 64; do grep -Eq "uitofp i$width " "$work/word_scalar_wide.ll"; done
# Set membership must still bound its ordinal before its bit test.
grep -Eq 'icmp ult i64 .* 256' "$work/word_scalar.ll"
# Existing array/subrange contracts deliberately compare in a wider signed
# domain after zero-extending unsigned sources; do not change those to ucmp.
for name in indexck_wide_ordinals indexck_word64_bad; do
  bin/pascal1981 --dialect extended -O0 -S "tests/corpus/golden/$name.pas" -o "$work/$name.ll"
done
for width in 8 16 32; do
  grep -Eq "zext i$width .* to i128" "$work/indexck_wide_ordinals.ll"
done
grep -Eq 'zext i64 .* to i128' "$work/indexck_word64_bad.ll"
grep -Eq 'icmp sge i128' "$work/indexck_word64_bad.ll"
grep -Eq 'icmp sle i128' "$work/indexck_word64_bad.ll"
echo 'PASS: scalar WORD DIV/MOD and ordering, all widths, both directives, O0-O3; CASE/set/bounds audit'
