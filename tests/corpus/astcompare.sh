#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# astcompare, the JSON AST comparator, and the frozen reference ASTs it checks.
set +e

write_pair() {
  printf '%s\n' "$1" > "$work/expected.json"
  printf '%s\n' "$2" > "$work/actual.json"
}

expect_match() {
  local label=$1
  shift
  if bin/astcompare "$@" >"$work/out" 2>"$work/err"; then
    pass "$label"
  else
    fail "$label"
    cat "$work/err" >&2
  fi
}

expect_mismatch() {
  local label=$1 diagnostic=$2
  shift 2
  local status=0
  bin/astcompare "$@" >"$work/out" 2>"$work/err" || status=$?
  if [ "$status" -ne 0 ] && grep -qF "$diagnostic" "$work/err"; then
    pass "$label"
  else
    fail "$label"
    echo "status: $status" >&2
    cat "$work/err" >&2
  fi
}

write_pair '{"name":"node","items":[1,true,false,null]}' \
  '{"name":"node","items":[1,true,false,null]}'
expect_match 'identical JSON matches' "$work/expected.json" "$work/actual.json"

write_pair '{"a":1,"b":{"x":2,"y":3}}' '{"b":{"y":3,"x":2},"a":1.0}'
expect_match 'object key order is ignored' "$work/expected.json" "$work/actual.json"

write_pair '{"resolved_type":"INTEGER","child":{"resolved_type":"REAL","x":1}}' \
  '{"resolved_type":"REAL","child":{"resolved_type":null,"x":1}}'
expect_match 'ignored keys are skipped recursively' --ignore-key resolved_type \
  "$work/expected.json" "$work/actual.json"

# Historically every option after the eighth was silently discarded.
write_pair '{"ninth":1,"child":{"tenth":1},"kept":7}' '{"ninth":2,"child":{"tenth":2},"kept":7}'
ignore_many=()
for key in a b c d e f g h ninth tenth; do ignore_many+=(--ignore-key "$key"); done
expect_match 'all ignore-key options are honored beyond eight' "${ignore_many[@]}" \
  "$work/expected.json" "$work/actual.json"
write_pair '{"ninth":1,"kept":7}' '{"ninth":2,"kept":8}'
expect_mismatch 'many ignored keys do not suppress unrelated differences' 'Mismatch at $.kept' \
  "${ignore_many[@]}" "$work/expected.json" "$work/actual.json"

write_pair '{"items":[1,2]}' '{"items":[2,1]}'
expect_mismatch 'array order remains significant' 'Mismatch at $.items[0]' \
  "$work/expected.json" "$work/actual.json"

write_pair '{"outer":{"wanted":1}}' '{"outer":{}}'
expect_mismatch 'missing keys report a JSON path' 'Mismatch at $.outer.wanted' \
  "$work/expected.json" "$work/actual.json"

write_pair '{"outer":{}}' '{"outer":{"extra":1}}'
expect_mismatch 'extra keys report a JSON path' 'Mismatch at $.outer.extra' \
  "$work/expected.json" "$work/actual.json"

write_pair '{"value":"1"}' '{"value":1}'
expect_mismatch 'different JSON types do not compare equal' 'JSON types differ' \
  "$work/expected.json" "$work/actual.json"

write_pair '{"items":[1]}' '{"items":[1,2]}'
expect_mismatch 'different array lengths fail' 'array lengths differ' \
  "$work/expected.json" "$work/actual.json"

printf '%s\n' '{broken' > "$work/actual.json"
expect_mismatch 'malformed JSON fails' 'malformed JSON in actual file' \
  "$work/expected.json" "$work/actual.json"

expect_mismatch 'missing files fail' 'cannot read expected file' \
  "$work/absent.json" "$work/actual.json"

expect_mismatch 'invalid command lines fail' 'Usage: astcompare' --bad-option \
  "$work/expected.json" "$work/actual.json"

check_frozen_ast() {
  local name=$1 label=$2
  local reference=tests/corpus/reference/ast/$name
  local actual_ast="$work/$name.ast.json"
  local actual_typed="$work/$name.typed.json"

  # The reference predates native per-index and per-operation flag snapshots;
  # those are checked separately by indexck_metadata.sh/mathck_metadata.sh,
  # not treated as reference parity.
  if bin/lexer < "$reference.pas" | bin/parser > "$actual_ast" &&
     bin/astcompare --ignore-key indexck --ignore-key rangeck --ignore-key meta_flags --ignore-key read_flags --ignore-key read_location --ignore-key location --ignore-key mathck --ignore-key op_location --ignore-key leading_comments --ignore-key trailing_comment \
       "$reference.ast.json" "$actual_ast"; then
    pass "native parser matches the frozen $label AST"
  else
    fail "native parser matches the frozen $label AST"
  fi

  if bin/typechecker < "$actual_ast" > "$actual_typed" &&
     bin/astcompare --ignore-key resolved_type --ignore-key indexck --ignore-key rangeck --ignore-key meta_flags --ignore-key read_flags --ignore-key read_location --ignore-key location --ignore-key mathck --ignore-key op_location \
       --ignore-key leading_comments --ignore-key trailing_comment \
       "$reference.typed.json" "$actual_typed"; then
    pass "native typechecker matches the frozen $label AST"
  else
    fail "native typechecker matches the frozen $label AST"
  fi
}

check_frozen_ast with_stmt 'WITH-statement'
check_frozen_ast case_stmt 'CASE-statement'
check_frozen_ast enum_types 'enumerated-type'
check_frozen_ast forward_decl 'forward-declaration'
check_frozen_ast pointer_record_graph 'pointer-record'

finish astcompare
