#!/usr/bin/env bash
# Verify the codegen backstop by bypassing the typechecker deliberately.
# The normal driver must instead reject all of these at typecheck time.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check() {
  local source=$1 expected=$2
  bin/lexer < "$source" > "$work/tokens"
  bin/parser < "$work/tokens" > "$work/ast"
  if bin/codegen < "$work/ast" > "$work/ir" 2> "$work/err"; then
    echo "FAIL: codegen accepted $source without typechecking" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$work/err"; then
    echo "FAIL: unexpected codegen error for $source" >&2
    grep . "$work/err" >&2
    exit 1
  fi
  echo "PASS: codegen guarded $source"
}

check tests/golden/set_base_assignment_rejected.pas 'codegen: assignment type mismatch for: s'
check tests/golden/set_base_operations_rejected.pas 'codegen: incompatible declared SET bases'
check tests/golden/set_base_comparison_rejected.pas 'codegen: incompatible declared SET bases'
check tests/golden/set_base_membership_rejected.pas 'codegen: incompatible declared SET base in IN'
check tests/golden/set_bounds_incompatible_rejected.pas 'codegen: incompatible declared SET bases'
check tests/golden/set_base_metadata_paths_rejected.pas 'codegen: assignment type mismatch for: WrongResult'
check tests/fixtures/codegen_set_base_call_guard.pas 'codegen: assignment type mismatch for: P'
check tests/fixtures/set_enum_identity_rejected.pas 'codegen: assignment type mismatch for: Wrong'
