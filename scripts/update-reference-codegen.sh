#!/usr/bin/env bash
# Regenerate frozen typed AST inputs for native codegen regression tests.
# This maintenance command uses the independent Python reference front end.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON=${PYTHON:-python3}

update_ast() {
  local source=$1 output=$2 temporary
  source=$(realpath "$source")
  temporary="$output.tmp"

  "$PYTHON" -m pascal1981.cli_lex "$source" |
    "$PYTHON" -m pascal1981.cli_parse --source-file "$source" --dialect extended |
    "$PYTHON" -m pascal1981.cli_typecheck --source-file "$source" --dialect extended \
      > "$temporary"
  mv "$temporary" "$output"
  echo "updated: $output"
}

update_ast tests/reference/codegen/host_launch_abi.pas \
  tests/reference/codegen/host_launch_abi.ast.json
update_ast tests/reference/codegen/device_kernel_attrs/kh.pas \
  tests/reference/codegen/device_kernel_attrs/kh.ast.json
update_ast tests/reference/codegen/host_device_attrs/kc.pas \
  tests/reference/codegen/host_device_attrs/kc.ast.json
