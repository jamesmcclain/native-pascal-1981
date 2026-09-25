#!/usr/bin/env bash
# Per-feature fixtures for pasboot. Each <name>.pas with a <name>.out is a
# PROGRAM that USES the testio unit: it is translated, compiled, linked with
# testio and run, and its output must equal <name>.out. Each <name>.pas with
# a <name>.err must be rejected, and the first line of <name>.err must
# appear in pasboot's diagnostic. Each <name>.pas with a <name>.inits is a
# PROGRAM whose generated main must call exactly those unit inits, in order.
set -euo pipefail
cd "$(dirname "$0")"
here="$(pwd)"
root="$(cd ../.. && pwd)"
pasboot="$root/bootstrap/build/pasboot"
runtime_lib="$root/runtime/build/libpascalrt.a"
CLANG="${CLANG:-${CC:-clang}}"
CFLAGS=(-O1 -fwrapv -w -I"$root/bootstrap")

[ -x "$pasboot" ] || make -C "$root/bootstrap" >/dev/null
[ -f "$runtime_lib" ] || make -C "$root/runtime" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$pasboot" testio.pas -o "$work/testio.c"
"$CLANG" "${CFLAGS[@]}" -c "$work/testio.c" -o "$work/testio.o"

pass=0
fail=0
for src in *.pas; do
  name="${src%.pas}"
  [ "$name" = testio ] && continue
  if [ -f "$name.out" ]; then
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log" &&
       "$CLANG" "${CFLAGS[@]}" "$work/$name.c" "$work/testio.o" "$runtime_lib" -o "$work/$name" 2>>"$work/$name.log" &&
       "$work/$name" >"$work/$name.actual" 2>>"$work/$name.log" &&
       cmp -s "$work/$name.actual" "$name.out"; then
      echo "PASS: $name"
      pass=$((pass + 1))
    else
      echo "FAIL: $name"
      cat "$work/$name.log"
      [ -f "$work/$name.actual" ] && diff "$name.out" "$work/$name.actual" || true
      fail=$((fail + 1))
    fi
  elif [ -f "$name.inits" ]; then
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log" &&
       grep -oE 'pascal_init_[A-Za-z0-9_]+\(\);' "$work/$name.c" >"$work/$name.actual" &&
       cmp -s "$work/$name.actual" "$name.inits"; then
      echo "PASS: $name"
      pass=$((pass + 1))
    else
      echo "FAIL: $name"
      cat "$work/$name.log"
      [ -f "$work/$name.actual" ] && diff "$name.inits" "$work/$name.actual" || true
      fail=$((fail + 1))
    fi
  elif [ -f "$name.err" ]; then
    expected="$(head -n 1 "$name.err")"
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log"; then
      echo "FAIL: $name (accepted; expected '$expected')"
      fail=$((fail + 1))
    elif grep -qF -- "$expected" "$work/$name.log"; then
      echo "PASS: $name (rejected)"
      pass=$((pass + 1))
    else
      echo "FAIL: $name (expected '$expected', got:)"
      cat "$work/$name.log"
      fail=$((fail + 1))
    fi
  else
    echo "FAIL: $name has neither $name.out nor $name.err"
    fail=$((fail + 1))
  fi
done

echo "pasboot fixtures: $pass passed, $fail failed"
[ "$fail" = 0 ]
