#!/usr/bin/env bash
# Native parser depth and resource-limit tests. No Python is required.
set -euo pipefail
cd "$(dirname "$0")/.."

for stage in lexer parser typechecker codegen; do
  if [ ! -x "bin/$stage" ]; then
    echo "error: bin/$stage not found; run make bootstrap first" >&2
    exit 1
  fi
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passed=0
failed=0

pass() {
  echo "PASS: $1"
  passed=$((passed + 1))
}

fail() {
  echo "FAIL: $1" >&2
  failed=$((failed + 1))
}

make_pointer_type() {
  local depth=$1 output=$2 i
  {
    printf 'PROGRAM TypeDepth;\nVAR p: '
    for ((i = 0; i < depth; i++)); do printf '^'; done
    printf 'INTEGER;\nBEGIN\nEND.\n'
  } > "$output"
}

make_expression() {
  local depth=$1 output=$2 i
  {
    printf 'PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n  a := '
    for ((i = 0; i < depth; i++)); do printf '('; done
    printf '1'
    for ((i = 0; i < depth; i++)); do printf ')'; done
    printf ';\nEND.\n'
  } > "$output"
}

make_statements() {
  local depth=$1 output=$2 i
  {
    printf 'PROGRAM S;\nVAR a: INTEGER;\nBEGIN\n  a := 0;\n'
    for ((i = 0; i < depth; i++)); do
      printf '  IF a = %d THEN a := 1 ELSE\n' "$i"
    done
    printf '  a := 2;\nEND.\n'
  } > "$output"
}

make_sibling_expressions() {
  local output=$1 sibling i
  {
    printf 'PROGRAM D;\nVAR a: INTEGER;\nBEGIN\n'
    for ((sibling = 0; sibling < 6; sibling++)); do
      printf '  a := '
      for ((i = 0; i < 62; i++)); do printf '('; done
      printf '1'
      for ((i = 0; i < 62; i++)); do printf ')'; done
      printf ';\n'
    done
    printf 'END.\n'
  } > "$output"
}

run_parser() {
  local source=$1 stem=$2
  if ! bin/lexer < "$source" > "$work_dir/$stem.tokens" \
       2> "$work_dir/$stem.lex.err"; then
    return 125
  fi
  bin/parser < "$work_dir/$stem.tokens" > "$work_dir/$stem.ast" \
    2> "$work_dir/$stem.err"
}

make_expression 63 "$work_dir/expr63.pas"
if run_parser "$work_dir/expr63.pas" expr63; then
  pass "expression nesting accepts depth 63"
else
  fail "expression nesting accepts depth 63"
  cat "$work_dir/expr63.err" >&2
fi

make_expression 64 "$work_dir/expr64.pas"
status=0
run_parser "$work_dir/expr64.pas" expr64 || status=$?
if [ "$status" -ne 0 ] &&
   grep -qF 'expression too complex' "$work_dir/expr64.err"; then
  pass "expression nesting rejects depth 64"
else
  fail "expression nesting rejects depth 64 with its diagnostic"
  cat "$work_dir/expr64.err" >&2
fi

make_statements 255 "$work_dir/stmt255.pas"
if run_parser "$work_dir/stmt255.pas" stmt255; then
  pass "statement nesting accepts depth 255"
else
  fail "statement nesting accepts depth 255"
  cat "$work_dir/stmt255.err" >&2
fi

make_statements 256 "$work_dir/stmt256.pas"
status=0
run_parser "$work_dir/stmt256.pas" stmt256 || status=$?
if [ "$status" -ne 0 ] &&
   grep -qF 'statements nested too deeply' "$work_dir/stmt256.err"; then
  pass "statement nesting rejects depth 256"
else
  fail "statement nesting rejects depth 256 with its diagnostic"
  cat "$work_dir/stmt256.err" >&2
fi

make_sibling_expressions "$work_dir/siblings.pas"
if run_parser "$work_dir/siblings.pas" siblings; then
  pass "expression depth unwinds between siblings"
else
  fail "expression depth unwinds between siblings"
  cat "$work_dir/siblings.err" >&2
fi

make_pointer_type 127 "$work_dir/type127.pas"
if run_parser "$work_dir/type127.pas" type127; then
  pass "type nesting accepts depth 127"
else
  fail "type nesting accepts depth 127"
  cat "$work_dir/type127.err" >&2
fi

make_pointer_type 128 "$work_dir/type128.pas"
status=0
run_parser "$work_dir/type128.pas" type128 || status=$?
if [ "$status" -ne 0 ] &&
   grep -qF 'type nested too deeply' "$work_dir/type128.err"; then
  pass "type nesting rejects depth 128"
else
  fail "type nesting rejects depth 128 with its diagnostic"
  cat "$work_dir/type128.err" >&2
fi

bounded_source=tests/fixtures/parser/should_fail/16_stray_rparen_in_compound.pas
if bin/lexer < "$bounded_source" > "$work_dir/stray.tokens" \
     2> "$work_dir/stray.lex.err"; then
  status=0
  (
    ulimit -v 131072
    timeout 5 bin/parser < "$work_dir/stray.tokens" \
      > "$work_dir/stray.ast" 2> "$work_dir/stray.err"
  ) || status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] &&
     grep -qF 'Parser Error: expected statement' "$work_dir/stray.err"; then
    pass "stray right parenthesis fails within time and memory limits"
  else
    fail "stray right parenthesis has a bounded parser failure"
    echo "parser status: $status" >&2
    cat "$work_dir/stray.err" >&2
  fi
else
  fail "lexer accepts stray-parenthesis regression fixture"
  cat "$work_dir/stray.lex.err" >&2
fi

assert_ast_rejected() {
  local stage=$1 input=$2 diagnostic=$3 label=$4 status=0
  if [ "$stage" = typechecker ]; then
    (
      ulimit -v 131072
      timeout 5 "bin/$stage" < "$input" > "$work_dir/$label.out" \
        2> "$work_dir/$label.err"
    ) || status=$?
  else
    timeout 5 "bin/$stage" < "$input" > "$work_dir/$label.out" \
      2> "$work_dir/$label.err" || status=$?
  fi
  if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] &&
     grep -qF "$diagnostic" "$work_dir/$label.err"; then
    pass "$label"
  else
    fail "$label"
    echo "$stage status: $status" >&2
    cat "$work_dir/$label.err" >&2
  fi
}

for source in parser typechecker codegen; do
  source_file="src/$source.pas"
  if [ "$source" = codegen ]; then
    source_file=src/cg_util.inc
    diagnostic_file=src/cg_util.pas
  else
    diagnostic_file="$source_file"
  fi
  if grep -Eq 'MAX_EXPR_DEPTH[[:space:]]*=[[:space:]]*64;' "$source_file" &&
     grep -qF 'deeper than 64' "$diagnostic_file" &&
     grep -Eq 'MAX_STMT_DEPTH[[:space:]]*=[[:space:]]*256;' "$source_file" &&
     grep -qF 'deeper than 256' "$diagnostic_file"; then
    pass "$source depth constants and diagnostics agree"
  else
    fail "$source depth constants and diagnostics agree"
  fi
done

assert_ast_rejected typechecker \
  tests/reference/depth/expr_depth_192.ast.json \
  'expression too complex' \
  'typechecker rejects an oversized expression AST'
assert_ast_rejected typechecker \
  tests/reference/depth/stmt_depth_512.ast.json \
  'statements nested too deeply' \
  'typechecker rejects an oversized statement AST'
assert_ast_rejected codegen \
  tests/reference/depth/expr_depth_192.typed.json \
  'codegen: expression too complex' \
  'codegen rejects an oversized expression AST'
assert_ast_rejected codegen \
  tests/reference/depth/stmt_depth_512.typed.json \
  'codegen: statements nested too deeply' \
  'codegen rejects an oversized statement AST'

echo "========================================"
echo "Depth results: $passed passed, $failed failed"
echo "========================================"
[ "$failed" -eq 0 ]
