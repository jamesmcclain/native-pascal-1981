#!/usr/bin/env bash
# Standalone compiler-stage command-line contract tests.
set -euo pipefail
cd "$(dirname "$0")/.."

for stage in lexer parser typechecker codegen; do
  if [ ! -x "bin/$stage" ]; then
    echo "error: bin/$stage is not executable; run make bootstrap first" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
pass=0
fail=0

pass_test() {
  echo "PASS: $1"
  pass=$((pass + 1))
}

fail_test() {
  echo "FAIL: $1" >&2
  fail=$((fail + 1))
}

compare_output() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if cmp -s "$expected" "$actual"; then
    pass_test "$label"
  else
    fail_test "$label"
    diff -u "$expected" "$actual" >&2 || true
  fi
}

expect_failure() {
  local stage="$1"
  local expected_error="$2"
  local label="$3"
  shift 3
  local status=0
  "bin/$stage" "$@" </dev/null > "$work_dir/stdout" 2> "$work_dir/stderr" || status=$?
  if [ "$status" -eq 0 ]; then
    fail_test "$label returns nonzero"
  else
    pass_test "$label returns nonzero"
  fi
  if [ -s "$work_dir/stdout" ]; then
    fail_test "$label keeps stdout empty"
  else
    pass_test "$label keeps stdout empty"
  fi
  if grep -qF -- "$expected_error" "$work_dir/stderr"; then
    pass_test "$label reports its error"
  else
    fail_test "$label reports its error"
    cat "$work_dir/stderr" >&2
  fi
}

source_file=tests/golden/01_hello.pas
bin/lexer < "$source_file" > "$work_dir/tokens"
bin/parser < "$work_dir/tokens" > "$work_dir/ast"
bin/typechecker < "$work_dir/ast" > "$work_dir/typed"
bin/codegen < "$work_dir/typed" > "$work_dir/ir"
pass_test 'standalone stages default successfully'

for dialect in vintage extended; do
  bin/parser --dialect "$dialect" < "$work_dir/tokens" > "$work_dir/parser-$dialect"
  compare_output "$work_dir/ast" "$work_dir/parser-$dialect" \
    "parser accepts --dialect $dialect without changing its AST"

  bin/typechecker --dialect "$dialect" < "$work_dir/ast" > "$work_dir/typechecker-$dialect"
  compare_output "$work_dir/typed" "$work_dir/typechecker-$dialect" \
    "typechecker accepts --dialect $dialect"

  bin/codegen --dialect "$dialect" < "$work_dir/typed" > "$work_dir/codegen-$dialect"
  compare_output "$work_dir/ir" "$work_dir/codegen-$dialect" \
    "codegen accepts --dialect $dialect"
done

for stage in parser typechecker codegen; do
  expect_failure "$stage" 'option requires a value: --dialect' \
    "$stage rejects a missing dialect value" --dialect
  expect_failure "$stage" "error: invalid dialect; expected 'vintage' or 'extended'" \
    "$stage rejects an invalid dialect" --dialect invalid
  expect_failure "$stage" 'unrecognized option: --unknown' \
    "$stage rejects an unknown option" --unknown
  expect_failure "$stage" 'accepts input only on standard input' \
    "$stage rejects a positional argument" unexpected.json

  status=0
  "bin/$stage" --help > "$work_dir/help" 2> "$work_dir/help.err" || status=$?
  if [ "$status" -eq 0 ] && grep -qF -- '--dialect' "$work_dir/help" && [ ! -s "$work_dir/help.err" ]; then
    pass_test "$stage --help describes the dialect option"
  else
    fail_test "$stage --help describes the dialect option"
    cat "$work_dir/help" >&2
    cat "$work_dir/help.err" >&2
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
