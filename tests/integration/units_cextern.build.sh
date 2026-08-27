#!/usr/bin/env bash
# Builds units_cextern.pas (a host PROGRAM) linked against a separately
# compiled UNIT implementation (units_cextern.cwrap.impl), demonstrating
# USES + separate compilation, which the single-file driver invocation
# alone can't do in one step (see tests/run.sh's <base>.build.sh hook).
#
# Invoked by tests/run.sh as: build.sh <driver-binary> <output-binary>
# from this fixture's own directory (so relative $INCLUDE paths resolve).
set -euo pipefail

driver="$1"
out_bin="$2"

bin_dir="$(dirname "$driver")"
repo_root="$(dirname "$bin_dir")"
runtime_lib="$repo_root/runtime/build/libpascalrt.a"
clang_bin="${CLANG:-${CC:-clang}}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

"$bin_dir/lexer" < units_cextern.cwrap.impl | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/cwrap.ll"
"$clang_bin" -O1 -c "$work_dir/cwrap.ll" -o "$work_dir/cwrap.o"

"$bin_dir/lexer" < units_cextern.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/cwrap.o" "$runtime_lib" -o "$out_bin"
