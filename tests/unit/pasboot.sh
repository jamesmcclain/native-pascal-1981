#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Per-feature fixtures for pasboot, the C bootstrap translator.
#
# Each <name>.pas with a <name>.out is a
# PROGRAM that USES the testio unit: it is translated, compiled, linked with
# testio and run, and its output must equal <name>.out. Each <name>.pas with
# a <name>.err must be rejected, and the first line of <name>.err must
# appear in pasboot's diagnostic. Each <name>.pas with a <name>.inits is a
# PROGRAM whose generated main must call exactly those unit inits, in order.
# The fixtures live in tests/unit/pasboot/.
require bootstrap/build/pasboot runtime/build/libpascalrt.a
pasboot="$ROOT/bootstrap/build/pasboot"
runtime_lib="$ROOT/runtime/build/libpascalrt.a"
CLANG="${CLANG:-${CC:-clang}}"
CFLAGS=(-O1 -fwrapv -w -I"$ROOT/bootstrap")
cd tests/unit/pasboot

"$pasboot" testio.pas -o "$work/testio.c"
"$CLANG" "${CFLAGS[@]}" -c "$work/testio.c" -o "$work/testio.o"

for src in *.pas; do
  name="${src%.pas}"
  [ "$name" = testio ] && continue
  if [ -f "$name.out" ]; then
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log" &&
       "$CLANG" "${CFLAGS[@]}" "$work/$name.c" "$work/testio.o" "$runtime_lib" -o "$work/$name" 2>>"$work/$name.log" &&
       "$work/$name" >"$work/$name.actual" 2>>"$work/$name.log" &&
       cmp -s "$work/$name.actual" "$name.out"; then
      pass "$name"
    else
      fail "$name"
      cat "$work/$name.log"
      [ -f "$work/$name.actual" ] && diff "$name.out" "$work/$name.actual" || true
    fi
  elif [ -f "$name.inits" ]; then
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log" &&
       grep -oE 'pascal_init_[A-Za-z0-9_]+\(\);' "$work/$name.c" >"$work/$name.actual" &&
       cmp -s "$work/$name.actual" "$name.inits"; then
      pass "$name"
    else
      fail "$name"
      cat "$work/$name.log"
      [ -f "$work/$name.actual" ] && diff "$name.inits" "$work/$name.actual" || true
    fi
  elif [ -f "$name.err" ]; then
    expected="$(head -n 1 "$name.err")"
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log"; then
      fail "$name (accepted; expected '$expected')"
    elif grep -qF -- "$expected" "$work/$name.log"; then
      pass "$name (rejected)"
    else
      fail "$name (expected '$expected', got:)"
      cat "$work/$name.log"
    fi
  else
    fail "$name has neither $name.out nor $name.err"
  fi
done

finish "pasboot fixtures"
