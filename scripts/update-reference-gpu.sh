#!/usr/bin/env bash
# Regenerate typed GPU ASTs through the independent Python front end.
set -euo pipefail

cd "$(dirname "$0")/.."
export PYTHONPATH=.

update() {
  local source=$1 output=${1%.pas}.typed.json
  python3 -m pascal1981.cli_lex "$source" |
    python3 -m pascal1981.cli_parse \
      --source-file "$source" --dialect extended |
    python3 -m pascal1981.cli_typecheck \
      --source-file "$source" --dialect extended > "$output"
  echo "updated: $output"
}

update tests/gpu/vadd.pas
update tests/gpu/host.pas
