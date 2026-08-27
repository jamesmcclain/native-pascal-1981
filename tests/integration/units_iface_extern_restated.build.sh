#!/usr/bin/env bash
# Builds a PROGRAM against a UNIT whose INTERFACE itself declares Helper
# EXTERN and whose IMPLEMENTATION re-states that EXTERN before defining only
# Local -- the split-implementation shape with the directive written on both
# sides.  units_iface_extern_restated.c supplies Helper.
#
# Invoked by tests/run.sh as: build.sh <driver-binary> <output-binary>
set -euo pipefail

driver="$1"
out_bin="$2"

bin_dir="$(dirname "$driver")"
repo_root="$(dirname "$bin_dir")"
runtime_lib="$repo_root/runtime/build/libpascalrt.a"
clang_bin="${CLANG:-${CC:-clang}}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

"$clang_bin" -c units_iface_extern_restated.c -o "$work_dir/helper.o"

"$bin_dir/lexer" < units_iface_extern_restated.esplit.impl | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/esplit.ll"
"$clang_bin" -O1 -c "$work_dir/esplit.ll" -o "$work_dir/esplit.o"

"$bin_dir/lexer" < units_iface_extern_restated.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/esplit.o" "$work_dir/helper.o" "$runtime_lib" -o "$out_bin"
