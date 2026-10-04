#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for dialect in vintage extended; do
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" tests/golden/scan_builtins.pas -o "$work/scan"
    "$work/scan" > "$work/output"
    diff -u tests/golden/scan_builtins.out "$work/output"
  done
  for entry in \
    "SCANEQ(1, 'x', 'abc')|exactly four arguments" \
    "SCANNE(TRUE, 'x', 'abc', 1)|count and position must be INTEGER" \
    "SCANEQ(1, 1, 'abc', 1)|pattern must be CHAR" \
    "SCANNE(1, 'x', 1, 1)|source must be STRING or LSTRING" \
    "SCANEQ(1, 'x', 'abc', TRUE)|count and position must be INTEGER" \
    "SCANEQ(40000, 'x', 'abc', 1)|out of range"; do
    expr=${entry%%|*}; diagnostic=${entry#*|}
    printf 'PROGRAM bad; BEGIN WRITELN(%s) END.\n' "$expr" > "$work/bad.pas"
    if bin/pascal1981 --dialect "$dialect" -S "$work/bad.pas" -o "$work/bad.ll" 2> "$work/error"; then
      echo "FAIL: admitted $expr" >&2; exit 1
    fi
    grep -qi "$diagnostic" "$work/error"
    test ! -s "$work/bad.ll"
  done
  # Shadowing still takes the user-routine path, not builtin dispatch.
  printf '%s\n' 'PROGRAM shadow;' 'FUNCTION SCANEQ(x: INTEGER): INTEGER;' \
    'BEGIN SCANEQ := x + 1 END;' 'BEGIN WRITELN(SCANEQ(6)) END.' > "$work/shadow.pas"
  bin/pascal1981 --dialect "$dialect" "$work/shadow.pas" -o "$work/shadow"
  test "$("$work/shadow")" = 7
done
# String initialization tracking is not implemented: reject enabled reads
# rather than silently reading an uninitialized length byte or character.
printf '%s\n' 'PROGRAM checked; VAR s: LSTRING(4);' \
  'BEGIN {$INITCK+} WRITELN(SCANEQ(4, '\''b'\'', s, 1)) END.' > "$work/checked.pas"
if bin/pascal1981 -S "$work/checked.pas" -o "$work/checked.ll" 2> "$work/error"; then
  echo 'FAIL: enabled unsupported string read' >&2; exit 1
fi
grep -q 'INITCK unsupported boundary: call consumer' "$work/error"
test ! -s "$work/checked.ll"
printf '%s\n' 'DEVICE INTERFACE; UNIT SCANDEVICE (run); PROCEDURE run; END;' \
  'DEVICE IMPLEMENTATION OF SCANDEVICE; PROCEDURE run; VAR n: INTEGER;' \
  'BEGIN n := SCANEQ(4, '\''b'\'', '\''aaba'\'', 1) END; .' > "$work/device.pas"
if bin/pascal1981 --dialect extended -S "$work/device.pas" -o "$work/device.ll" 2> "$work/error"; then
  echo 'FAIL: admitted host scan in DEVICE code' >&2; exit 1
fi
grep -q 'SCANEQ/SCANNE are host-only' "$work/error"
test ! -s "$work/device.ll"
echo 'PASS: scan builtin semantics, argument validation, shadowing and boundaries'
