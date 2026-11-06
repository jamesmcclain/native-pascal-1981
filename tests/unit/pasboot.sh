#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Per-feature fixtures for pasboot, the C bootstrap translator.
#
# Each <name>.pas with a <name>.out is a
# PROGRAM that USES the testio unit: it is translated, compiled, linked with
# testio and run, and its output must equal <name>.out. With a <name>.rterr
# as well, the program must instead fail at run time after that output, and
# its stderr must be exactly <name>.rterr. Each <name>.pas with
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
  if [ -f "$name.rterr" ]; then
    status=0
    if "$pasboot" "$src" -o "$work/$name.c" 2>"$work/$name.log" &&
       "$CLANG" "${CFLAGS[@]}" "$work/$name.c" "$work/testio.o" "$runtime_lib" -o "$work/$name" 2>>"$work/$name.log"; then
      # The subshell absorbs bash's own "Aborted" job report.
      ("$work/$name" >"$work/$name.actual" 2>"$work/$name.err"; exit) 2>/dev/null || status=$?
      if [ "$status" -ne 0 ] && cmp -s "$work/$name.actual" "$name.out" &&
         cmp -s "$work/$name.err" "$name.rterr"; then
        pass "$name (run-time error)"
      else
        fail "$name (status $status)"
        diff "$name.out" "$work/$name.actual" || true
        diff "$name.rterr" "$work/$name.err" || true
      fi
    else
      fail "$name"
      cat "$work/$name.log"
    fi
  elif [ -f "$name.out" ]; then
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

# The arithmetic edges again, without -fwrapv and under UBSan: unchecked
# wrapping, MIN DIV -1 and FOR at the maximum must be defined C on their own.
# The checks trap in place, so no sanitizer runtime is needed; a compiler
# without -fsanitize-trap skips this check.
name=arith_edges
ubsan=(-O1 -w -fsanitize=undefined -fsanitize-trap=undefined -I"$ROOT/bootstrap")
if ! echo 'int main(void){return 0;}' |
     "$CLANG" -fsanitize=undefined -fsanitize-trap=undefined -x c - -o "$work/ubsan-probe" 2>/dev/null; then
  skip "$name under UBSan" "$CLANG lacks -fsanitize-trap=undefined"
elif "$pasboot" "$name.pas" -o "$work/$name.c" 2>"$work/$name.log" &&
     "$CLANG" "${ubsan[@]}" -c "$work/testio.c" -o "$work/testio-ubsan.o" 2>>"$work/$name.log" &&
     "$CLANG" "${ubsan[@]}" "$work/$name.c" "$work/testio-ubsan.o" "$runtime_lib" -o "$work/$name-ubsan" 2>>"$work/$name.log" &&
     "$work/$name-ubsan" >"$work/$name-ubsan.actual" 2>>"$work/$name.log" &&
     cmp -s "$work/$name-ubsan.actual" "$name.out"; then
  pass "$name under UBSan without -fwrapv"
else
  fail "$name under UBSan without -fwrapv"
  cat "$work/$name.log"
fi

finish "pasboot fixtures"
