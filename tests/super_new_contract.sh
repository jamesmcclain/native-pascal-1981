#!/usr/bin/env bash
# Hardened NEW failures: inspect selected slots via a test-only C/linker harness.
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
driver=bin/pascal1981-native
cc=${CC:-clang}
bash tests/run.sh tests/golden/super_new_hardened.pas
"$cc" -Wall -Wextra -Werror tests/super_new_runtime.c runtime/build/libpascalrt.a \
  -Wl,--wrap=malloc -o "$work/runtime"
"$work/runtime"
"$driver" --dialect extended -O0 -S tests/descriptor/new_failures.pas -o "$work/fail.ll"
reasons=('upper bound is below declared lower' 'upper bound is outside declared index domain'
         'upper bound is not representable' 'upper bound is outside declared index domain'
         'allocation failed' 'upper bound is below declared lower')
for opt in 0 2; do
"$cc" -O"$opt" "$work/fail.ll" tests/super_new_publication.c runtime/build/libpascalrt.a \
  -Wl,--wrap=malloc,--wrap=free,--wrap=abort -o "$work/fail"
for mode in 1 2 3 4 5 6; do
  code=0
  printf '%s\n' "$mode" | "$work/fail" >"$work/out" 2>"$work/err" || code=$?
  printf 'runtime error: NEW SUPER ARRAY %s\n' "${reasons[mode-1]}" >"$work/expected.err"
  printf 'PASS: destination unchanged except bound-expression side effects\n' >"$work/expected.out"
  if [ "$code" -ne 134 ] || ! cmp -s "$work/out" "$work/expected.out" || ! cmp -s "$work/err" "$work/expected.err"; then
    echo "FAIL: NEW publication mode $mode (exit $code)"; exit 1
  fi
  echo "PASS: NEW failure $mode at O$opt: once-only selection/bound and transactional publication"
done
done
"$driver" --dialect extended tests/descriptor/new_size_overflow.pas -o "$work/overflow"
code=0
{ "$work/overflow" >"$work/out" 2>"$work/err"; } 2>/dev/null || code=$?
printf 'runtime error: NEW SUPER ARRAY byte size overflows\n' >"$work/expected.err"
[ "$code" -eq 134 ] && [ ! -s "$work/out" ] && cmp -s "$work/err" "$work/expected.err"
echo 'PASS: source-level wide byte-size overflow under INDEXCK-'
"$driver" --dialect extended -S tests/descriptor/new_wide_stride.pas -o "$work/wide.ll"
grep -Eq 'call ptr @pas_super_new\(i64 2, i32 0, i64 2, i64 -32768, i64 32767, i64 4294967296, i64 1\)' "$work/wide.ll"
"$driver" --dialect extended -S tests/golden/super_new_hardened.pas -o "$work/valid.ll"
grep -Eq 'call ptr @pas_super_new\(.*i64 16, i64 16\)' "$work/valid.ll"
python3 - "$work/fail.ll" <<'PY'
import re, sys
ir = open(sys.argv[1]).read()
main = re.search(r'define i32 @main\(.*?\n\}', ir, re.S).group()
# Initial NEW plus both alternatives. Every publication must be a full store
# after its checked allocator call; there are no pre-call field writes.
assert len(re.findall(r'call ptr @pas_super_new', main)) == 3
for segment in main.split('call ptr @pas_super_new')[1:]:
    segment = segment.split('call ptr @pas_super_new')[0]
    assert re.search(r'insertvalue \{ ptr, i64 \} .*?, ptr %\w+, 0', segment)
    assert re.search(r'store \{ ptr, i64 \} %\w+, ptr ', segment)
assert not re.search(r'store (?:ptr|i64) .*?, ptr @slots', main)
assert 'call ptr @malloc' not in main
print('PASS: validated allocation precedes whole-value publication; wide/aligned strides')
PY
