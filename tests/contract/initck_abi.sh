#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INITCK on/off twins agree on output, Pascal ABI and descriptor layout.
#
# Unsupported descriptor/aggregate result reads are explicitly INITCK- in both.
cp tests/contract/fixtures/initck_validation_abi.pas "$work/on.pas"
# Keep the extra trailing newline emitted by the former Python print.
{
  sed 's/{$INITCK+}/{$INITCK-}/g' "$work/on.pas"
  printf '\n'
} > "$work/off.pas"
printf '2:4:-32768\n4:0\n4:6\n2:6:12\n2:4:-32768\n4:0\n4:6\n0:-32768\n16:16:32\n' > "$work/expected"
for dialect in vintage extended; do
  for opt in 0 1 2 3; do
    for mode in on off; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$mode.pas" \
        -o "$work/run" 2> "$work/err"
      test ! -s "$work/err"
      "$work/run" > "$work/$mode.out" 2> "$work/err"
      test ! -s "$work/err"
      diff -u "$work/expected" "$work/$mode.out"
      bin/pascal1981 --dialect "$dialect" -O"$opt" -S "$work/$mode.pas" \
        -o "$work/$mode.ll" 2> "$work/err"
      test ! -s "$work/err"
    done
    diff -u "$work/off.out" "$work/on.out"
    # Optimizers may inline/eliminate Pascal calls. Pin the source ABI in O0 IR.
    if [ "$opt" = 0 ]; then
      python3 tests/contract/fixtures/initck_abi/abi-signatures.py "$work/on.ll" "$work/off.ll"
    fi
  done
done
echo 'PASS: INITCK initialized output/ABI/layout twins (both dialects, O0/O1/O2/O3)'
