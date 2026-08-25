#!/usr/bin/env bash
# Regenerate frozen ASTs through the independent Python front end.
set -euo pipefail

cd "$(dirname "$0")/.."
export PYTHONPATH=.

update() {
  local source=$1
  local ast=${source%.pas}.ast.json
  local typed=${source%.pas}.typed.json

  python3 -m pascal1981.cli_lex "$source" |
    python3 -m pascal1981.cli_parse \
      --source-file "$source" --dialect extended > "$ast"
  python3 -m pascal1981.cli_typecheck \
    --source-file "$source" --dialect extended < "$ast" > "$typed"
  echo "updated: $ast"
  echo "updated: $typed"
}

update tests/reference/ast/with_stmt.pas
update tests/reference/ast/case_stmt.pas
update tests/reference/ast/enum_types.pas
update tests/reference/ast/forward_decl.pas
update tests/reference/ast/pointer_record_graph.pas
