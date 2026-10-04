#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Release-gate fixtures: checked success/failure, non-sentinel values,
# partial aggregates/aliases/calls across flag regions, and compile-only
# disabled twins for uninitialized reads.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ulimit -c 0
for kind in ok fail values mixed_ok mixed_fail; do
  cp "tests/fixtures/initck_validation_$kind.pas" "$work/$kind-on.pas"
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
      python3 - "$work/fail-on.ll" "$work/fail-off.ll" <<'PY'
import re, sys
on, off = (open(p).read() for p in sys.argv[1:])
# A value actual is a read even when the callee ignores it. Verify the
# metadata-only branch and terminating failure precede the FIRST data load,
# and that the native load precedes the call. Disabled IR retains that same
# unsafe read but no guard: it is evidence about lowering, not program output.
probe = re.search(r'define void @probe\(.*?^}', on, re.M | re.S).group()
state = probe.index('load i1, ptr %initck.unset,')
load = probe.index('load i16, ptr %unset,')
call = probe.index('call void @ignore(')
assert state < load < call
assert 'load i16, ptr %unset,' not in probe[:state]
region = probe[state:load]
assert re.search(r'br i1 %initck.ready\d*, label %initck.ok\d*, label %initck.bad\d*', region)
assert 'call void @pas_initck_error' in region
assert 'unreachable' in region
assert re.search(r'initck.ok\d*:', region)
assert 'load i16, ptr %unset,' in off
assert not re.search(r'call void @pas_initck_(error|fail)', off)
PY
      python3 - "$work/values-on.ll" "$work/values-off.ll" <<'PY'
import re, sys
on, off = (open(p).read() for p in sys.argv[1:])
# Replacement for the metadata-only baseline's on/off identical-IR oracle:
# supported source reads now have guards, while opt-out keeps state tracking.
assert on != off
assert not re.search(r'call void @pas_initck_(error|fail)', off)
# Coordinates refer to the persistent values fixture: scalar and pointer
# reads, whole-record copy, array element, heap leaf, formal and result.
for helper, line, column in (
    ('error', 17, 11), ('error', 17, 57),
    ('fail', 24, 45), ('fail', 26, 11), ('fail', 28, 28),
    ('fail', 6, 19), ('fail', 6, 21),
):
    assert re.search(r'call void @pas_initck_' + helper +
                     r'\([^\n]*i32 ' + str(line) + r', i32 ' + str(column) + r'\)', on), (
        helper, line, column)
# INITCK- is not a switch that removes instrumentation: unchecked producers
# and copies must retain state for later enabled reads and routine boundaries.
for ir in (on, off):
    for slot, shape in (('x', 'i1'), ('p', 'i1'), ('v', 'i1'),
                        ('result', 'i1'), ('a', '[2 x i1]'),
                        ('values', '[2 x i1]')):
        assert '%initck.' + slot + ' = alloca ' + shape in ir
    for helper in ('copy', 'heap_new', 'heap_at', 'heap_dispose'):
        assert re.search(r'call (?:void|ptr) @pas_initck_' + helper + r'\(', ir)
    assert 'store i1' in ir and 'ptr @pas_initck_ret' in ir
PY
    fi
  done
done
echo 'PASS: INITCK release fixtures, values, partial aggregates, aliases, mixed flags, calls, enabled/disabled IR (O0/O1/O2/O3)'
