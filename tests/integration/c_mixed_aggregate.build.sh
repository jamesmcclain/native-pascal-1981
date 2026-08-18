#!/usr/bin/env bash
# The [C] callees this fixture passes aggregates to are real clang-compiled
# C functions; the driver only forwards -I/-L/-l to its own clang link step,
# so they are staged into a temporary static library it can be told to link.
set -euo pipefail

lib_dir="$(mktemp -d)"
trap 'rm -rf "$lib_dir"' EXIT

"${CC:-clang}" -c c_mixed_aggregate.c -o "$lib_dir/callees.o"
ar rcs "$lib_dir/libmixedcallees.a" "$lib_dir/callees.o"

"$1" c_mixed_aggregate.pas -o "$2" -L"$lib_dir" -lmixedcallees
