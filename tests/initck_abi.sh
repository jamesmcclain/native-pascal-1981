#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Initialized on/off twins: observable output, Pascal ABI and descriptor layout.
# Unsupported descriptor/aggregate result reads are explicitly INITCK- in both.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp tests/fixtures/initck_validation_abi.pas "$work/on.pas"
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
      python3 - "$work/on.ll" "$work/off.ll" <<'PY'
import re, sys
on, off = (open(p).read() for p in sys.argv[1:])
names = 'Observe|Rebind|View|TakePair|Echo|EchoHolder|ReturnPair|Scalar'
def signatures(ir):
    result = []
    for line in ir.splitlines():
        m = re.search(r'(define|call) (.*?) @(' + names + r')\((.*)\)', line)
        if m:
            # Instrumentation can renumber SSA values, but not alter ABI types,
            # attributes, order, number of calls, or supplied constants.
            args = re.sub(r'%[\w.]+', '%', m[4])
            result.append(f'{m[1]} {m[2]} @{m[3]}({args})')
    return result
expected = '''define void @Observe(i64 %, i64 %)
define void @Rebind(ptr %, i64 %, i64 %)
define void @View(ptr %)
define void @TakePair(ptr byval({ { ptr, i64 }, { ptr, i64 } }) align 8 %)
define { i64, i64 } @Echo(i64 %, i64 %)
define { i64, i64 } @EchoHolder(i64 %, i64 %)
define void @ReturnPair(ptr noalias sret({ { ptr, i64 }, { ptr, i64 } }) align 8 %, ptr byval({ { ptr, i64 }, { ptr, i64 } }) align 8 %)
define i16 @Scalar(i16 %)
call void @Observe(i64 %, i64 %)
call void @View(ptr %)
call void @TakePair(ptr byval({ { ptr, i64 }, { ptr, i64 } }) align 8 %)
call void @Rebind(ptr %, i64 %, i64 %)
call void @Observe(i64 %, i64 %)
call { i64, i64 } @Echo(i64 %, i64 %)
call { i64, i64 } @EchoHolder(i64 %, i64 %)
call void @ReturnPair(ptr noalias sret({ { ptr, i64 }, { ptr, i64 } }) align 8 %, ptr byval({ { ptr, i64 }, { ptr, i64 } }) align 8 %)
call void @Observe(i64 %, i64 %)
call void @View(ptr %)
call void @TakePair(ptr byval({ { ptr, i64 }, { ptr, i64 } }) align 8 %)
call i16 @Scalar(i16 0)
call i16 @Scalar(i16 -32768)'''.splitlines()
for ir in (on, off):
    actual = signatures(ir)
    assert actual == expected, '\n'.join(actual)
    # State remains separate from the program's {data, upper} descriptor.
    for name, ty in [('p', '{ ptr, i64 }'), ('q', '{ ptr, i64 }'),
                     ('alias', '{ ptr, i64 }'), ('h', '{ { ptr, i64 } }'),
                     ('pairslot', '{ { ptr, i64 }, { ptr, i64 } }')]:
        assert f'%{name} = alloca {ty}, align 8' in ir
    assert re.search(r'load \{ ptr, i64 \}, ptr', ir)
    assert re.search(r'store \{ ptr, i64 \} .*?, ptr %p, align 8', ir)
    assert not re.search(r'getelementptr.*i64 -8', ir)
assert 'call void @pas_initck_fail' in on or 'call void @pas_initck_error' in on
assert not re.search(r'call void @pas_initck_(fail|error)', off)
print('PASS: pinned value/VAR/CONST, coerced/byval/sret ABI and separate descriptor layout')
PY
    fi
  done
done
echo 'PASS: INITCK initialized output/ABI/layout twins (both dialects, O0/O1/O2/O3)'
