#!/usr/bin/env bash
# A MODULE compiland exports routines consumed through a separate UNIT header.
set -euo pipefail

driver="$1"
out_bin="$2"
bin_dir="$(dirname "$driver")"
repo_root="$(dirname "$bin_dir")"
runtime_lib="$repo_root/runtime/build/libpascalrt.a"
clang_bin="${CLANG:-${CC:-clang}}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

"$bin_dir/lexer" < module_compiland.module | "$bin_dir/parser" | \
  "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/module.ll"
"$clang_bin" -O1 -c "$work_dir/module.ll" -o "$work_dir/module.o"
"$bin_dir/lexer" < module_compiland.pas | "$bin_dir/parser" | \
  "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/module.o" "$runtime_lib" -o "$out_bin"
