#!/usr/bin/env bash
# Distinct enum declarations must fail in the checker, not later in codegen.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for dialect in vintage extended; do
  for kind in compatible rejected; do
    if [ "$kind" = compatible ]; then
      src=tests/golden/set_enum_identity_compatible.pas
    else
      src=tests/fixtures/set_enum_identity_rejected.pas
    fi
    bin/lexer --dialect "$dialect" < "$src" > "$work/tokens"
    bin/parser --dialect "$dialect" < "$work/tokens" > "$work/ast"
    if [ "$kind" = compatible ]; then
      bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typed" 2> "$work/err"
      [ ! -s "$work/err" ] || { echo "unexpected enum checker error in $dialect" >&2; exit 1; }
      bin/codegen --dialect "$dialect" < "$work/typed" > "$work/ir" 2> "$work/err"
      [ ! -s "$work/err" ] || { echo "unexpected enum codegen error in $dialect" >&2; exit 1; }
    else
      if bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typed" 2> "$work/err"; then
        echo "enum identity mismatch accepted in $dialect" >&2
        exit 1
      fi
      [ "$(grep -Fc 'Incompatible set base types' "$work/err")" -eq 12 ]
      [ "$(wc -l < "$work/err")" -eq 13 ]
      head -1 "$work/err" | grep -Fxq 'Type checking failed:'
    fi
    echo "PASS: $dialect enum SET typecheck $kind"
  done
done
