#!/usr/bin/env bash
# Builds units_cextern_bare.pas (a host PROGRAM) linked against a separately
# compiled UNIT implementation (units_cextern_bare.cbare.impl), demonstrating
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

"$bin_dir/lexer" < units_cextern_bare.cbare.impl | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/cbare.ll"
"$clang_bin" -O1 -c "$work_dir/cbare.ll" -o "$work_dir/cbare.o"

"$bin_dir/lexer" < units_cextern_bare.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/cbare.o" "$runtime_lib" -o "$out_bin"
