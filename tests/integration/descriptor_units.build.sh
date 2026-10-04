#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/temp-env.sh"
# Genuine separate caller/callee compilations, not a single in-module call.
set -euo pipefail
driver="$1"
out_bin="$2"
repo_root="$(dirname "$(dirname "$driver")")"
clang_bin="${CLANG:-${CC:-clang}}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$driver" --dialect extended -S descriptor_units.api.impl -o "$work/api.ll"
"$clang_bin" -O1 -c "$work/api.ll" -o "$work/api.o"
"$driver" --dialect extended -S descriptor_units.pas -o "$work/main.ll"
"$clang_bin" -O1 "$work/main.ll" "$work/api.o" "$repo_root/runtime/build/libpascalrt.a" -o "$out_bin"
