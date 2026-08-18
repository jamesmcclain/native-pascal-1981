#!/usr/bin/env bash
# Builds a diamond USES graph: beta and gamma both depend on alpha.  Each
# compiland gets the interfaces it needs spliced in, then all objects link.
set -euo pipefail

driver="$1"
out_bin="$2"
bin_dir="$(dirname "$driver")"
repo_root="$(dirname "$bin_dir")"
runtime_lib="$repo_root/runtime/build/libpascalrt.a"
clang_bin="${CLANG:-${CC:-clang}}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

for unit in alpha beta gamma; do
  "$bin_dir/lexer" < "units_graph.$unit.impl" | "$bin_dir/parser" | \
    "$bin_dir/typechecker" | "$bin_dir/codegen" > "$work_dir/$unit.ll"
  "$clang_bin" -O1 -c "$work_dir/$unit.ll" -o "$work_dir/$unit.o"
done

"$bin_dir/lexer" < units_graph.pas | "$bin_dir/parser" | "$bin_dir/typechecker" | \
  "$bin_dir/codegen" > "$work_dir/host.ll"
"$clang_bin" -O1 "$work_dir/host.ll" "$work_dir/alpha.o" "$work_dir/beta.o" \
  "$work_dir/gamma.o" "$runtime_lib" -o "$out_bin"
