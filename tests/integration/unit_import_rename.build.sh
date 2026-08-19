#!/usr/bin/env bash
# Builds unit_import_rename.pas (a host PROGRAM that renames its imports via
# `USES mathutil (Sq, Cb)`) linked against a separately compiled UNIT
# implementation exporting Square/Cube under their real names -- proving the
# alias resolves through to the real linked symbol, and that the original
# export names still link cleanly. See units_basic.build.sh for the general
# shape of this two-compiland build.
set -euo pipefail

driver="$1"
out_bin="$2"

bin_dir="$(dirname "$driver")"
repo_root="$(dirname "$bin_dir")"
runtime_lib="$repo_root/runtime/build/libpascalrt.a"
clang_bin="${CLANG:-${CC:-clang}}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

"$bin_dir/lexer" < unit_import_rename.mathutil.impl | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/mathutil.ll"
"$clang_bin" -O1 -c "$work_dir/mathutil.ll" -o "$work_dir/mathutil.o"

"$bin_dir/lexer" < unit_import_rename.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/mathutil.o" "$runtime_lib" -o "$out_bin"
