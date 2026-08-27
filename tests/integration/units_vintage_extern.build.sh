#!/usr/bin/env bash
# Builds a PROGRAM against a UNIT whose INTERFACE is implemented partly in
# Pascal and partly in C -- the 1981 manual's split-implementation shape.
# vsplit's IMPLEMENTATION declares Helper with the EXTERN directive at its
# start and defines only Local; units_vintage_extern.c supplies Helper.
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

"$clang_bin" -c units_vintage_extern.c -o "$work_dir/helper.o"

"$bin_dir/lexer" < units_vintage_extern.vsplit.impl | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/vsplit.ll"
"$clang_bin" -O1 -c "$work_dir/vsplit.ll" -o "$work_dir/vsplit.o"

"$bin_dir/lexer" < units_vintage_extern.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/vsplit.o" "$work_dir/helper.o" "$runtime_lib" -o "$out_bin"
