#!/usr/bin/env bash
# Stage-only checks: full named-index goldens still require codegen lowering.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check() {
  local dialect=$1 source=$2 expected=$3
  bin/lexer --dialect "$dialect" < "$source" |
    bin/parser --dialect "$dialect" > "$work/ast.json"
  if [[ -z "$expected" ]]; then
    bin/typechecker --dialect "$dialect" < "$work/ast.json" > "$work/typed.json" 2> "$work/error"
  else
    if bin/typechecker --dialect "$dialect" < "$work/ast.json" > "$work/typed.json" 2> "$work/error"; then
      echo "Expected typecheck failure: $source ($dialect)" >&2
      exit 1
    fi
    grep -Fq "$expected" "$work/error"
  fi
}

for dialect in vintage extended; do
  for kind in boolean enum subrange char; do
    check "$dialect" "tests/golden/array_named_$kind.pas" ''
    echo "PASS: named $kind index typechecks ($dialect)"
  done

  printf '%s\n' 'PROGRAM t(output); TYPE Color = (red, green, blue); Small = green..blue; Alias = Small; VAR a: ARRAY [Alias] OF INTEGER; BEGIN END.' > "$work/enum_subrange.pas"
  check "$dialect" "$work/enum_subrange.pas" ''
  printf '%s\n' 'PROGRAM t(output); TYPE Bad = 4..2; VAR a: ARRAY [Bad] OF INTEGER; BEGIN END.' > "$work/reversed.pas"
  check "$dialect" "$work/reversed.pas" 'Array index type has reversed ordinal bounds'
  printf '%s\n' 'PROGRAM t(output); VAR a: ARRAY [missing] OF INTEGER; BEGIN END.' > "$work/missing.pas"
  check "$dialect" "$work/missing.pas" 'Unknown type name'
  printf '%s\n' 'PROGRAM t(output); CONST V = 1; VAR a: ARRAY [V] OF INTEGER; BEGIN END.' > "$work/value.pas"
  check "$dialect" "$work/value.pas" 'Array index requires a type name, not a value: V'
  printf '%s\n' 'PROGRAM t(output); TYPE R = REAL; VAR a: ARRAY [R] OF INTEGER; BEGIN END.' > "$work/real.pas"
  check "$dialect" "$work/real.pas" 'Array index type must be ordinal'
  printf '%s\n' 'PROGRAM t(output); TYPE R = RECORD x: INTEGER END; VAR a: ARRAY [R] OF INTEGER; BEGIN END.' > "$work/record.pas"
  check "$dialect" "$work/record.pas" 'Array index type must be ordinal'
  printf '%s\n' 'PROGRAM t(output); TYPE BOOLEAN = REAL; VAR a: ARRAY [BOOLEAN] OF INTEGER; BEGIN END.' > "$work/shadow.pas"
  check "$dialect" "$work/shadow.pas" 'Array index type must be ordinal'
  echo "PASS: alias bounds and invalid type names ($dialect)"
done
