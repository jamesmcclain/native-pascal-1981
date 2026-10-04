#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# C unit tests of the runtime library.
#
# Each tests/unit/runtime_*.c is a
# program linked against libpascalrt.a that exits 0 when its checks hold.
set +e
require runtime/build/libpascalrt.a
for source in tests/unit/runtime_*.c; do
  name=$(basename "$source" .c)
  if ! "${CC:-clang}" -Wall -Wextra -o "$work/$name" "$source" runtime/build/libpascalrt.a \
      2> "$work/$name.log"; then
    fail "$name" 'does not compile'
    cat "$work/$name.log" >&2
  elif "$work/$name" > "$work/$name.log" 2>&1; then
    pass "$name"
  else
    fail "$name"
    cat "$work/$name.log" >&2
  fi
done
finish "runtime C units"
