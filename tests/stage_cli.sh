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

(
  cd src
  ../bin/lexer < argparse.pas > "$work_dir/bootstrap.tokens"
  ../bin/parser < "$work_dir/bootstrap.tokens" > "$work_dir/bootstrap.ast"
)
status=0
bin/typechecker < "$work_dir/bootstrap.ast" > "$work_dir/bootstrap.typed" \
  2> "$work_dir/bootstrap.err" || status=$?
if [ "$status" -ne 0 ] &&
   grep -qF 'Type requires the extended dialect: INTEGER32' \
     "$work_dir/bootstrap.err"; then
  pass_test 'omitted bootstrap dialect rejects extended compiler source'
else
  fail_test 'omitted bootstrap dialect rejects extended compiler source'
  cat "$work_dir/bootstrap.err" >&2
fi
if bin/typechecker --dialect extended < "$work_dir/bootstrap.ast" \
     > "$work_dir/bootstrap-extended.typed" 2> "$work_dir/bootstrap-extended.err"; then
  pass_test 'explicit extended bootstrap dialect accepts compiler source'
else
  fail_test 'explicit extended bootstrap dialect accepts compiler source'
  cat "$work_dir/bootstrap-extended.err" >&2
fi

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

# The token JSON is a stage interface, so the parser must not narrow its
# integer fields to the dialect's 16-bit INTEGER. A LSTRING capacity past
# 32767 came out of TRUNC wrapped (40000 as -25536), and a column past 32767
# would be poison in the same way. The native lexer's own column counter
# wraps at 16 bits today, but that is the lexer's limitation, not the
# parser's contract -- both regressions are replayed straight into the
# stage's stdin here.
wide_cap_src="$work_dir/wide_cap.pas"
cat > "$wide_cap_src" <<'EOF'
PROGRAM WideCap;
VAR s: LSTRING(40000);
BEGIN
END.
EOF
bin/lexer < "$wide_cap_src" > "$work_dir/wide_cap.tokens"
if bin/parser < "$work_dir/wide_cap.tokens" > "$work_dir/wide_cap.ast" 2> "$work_dir/wide_cap.err" \
   && grep -q '"param":[[:space:]]*40000' "$work_dir/wide_cap.ast"; then
  pass_test 'parser keeps a STRING/LSTRING capacity past 16 bits intact'
else
  fail_test 'parser keeps a STRING/LSTRING capacity past 16 bits intact'
  cat "$work_dir/wide_cap.err" >&2
fi
sed 's/"column":[[:space:]]*[0-9][0-9]*/"column":40000/g' \
  "$work_dir/wide_cap.tokens" > "$work_dir/wide_col.tokens"
if bin/parser < "$work_dir/wide_col.tokens" > "$work_dir/wide_col.ast" 2> "$work_dir/wide_col.err" \
   && cmp -s "$work_dir/wide_cap.ast" "$work_dir/wide_col.ast"; then
  pass_test 'parser accepts a column past 16 bits unchanged'
else
  fail_test 'parser accepts a column past 16 bits unchanged'
  cat "$work_dir/wide_col.err" >&2
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
