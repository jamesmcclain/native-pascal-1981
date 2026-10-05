#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Standalone compiler-stage command-line contract tests.

for stage in lexer parser typechecker codegen; do
  if [ ! -x "bin/$stage" ]; then
    echo "error: bin/$stage is not executable; run make bootstrap first" >&2
    exit 1
  fi
done

compare_output() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if cmp -s "$expected" "$actual"; then
    pass "$label"
  else
    fail "$label"
    diff -u "$expected" "$actual" >&2 || true
  fi
}

expect_failure() {
  local stage="$1"
  local expected_error="$2"
  local label="$3"
  shift 3
  local status=0
  "bin/$stage" "$@" </dev/null > "$work/stdout" 2> "$work/stderr" || status=$?
  if [ "$status" -eq 0 ]; then
    fail "$label returns nonzero"
  else
    pass "$label returns nonzero"
  fi
  if [ -s "$work/stdout" ]; then
    fail "$label keeps stdout empty"
  else
    pass "$label keeps stdout empty"
  fi
  if grep -qF -- "$expected_error" "$work/stderr"; then
    pass "$label reports its error"
  else
    fail "$label reports its error"
    cat "$work/stderr" >&2
  fi
}

source_file=tests/corpus/golden/01_hello.pas
bin/lexer < "$source_file" > "$work/tokens"
bin/parser < "$work/tokens" > "$work/ast"
bin/typechecker < "$work/ast" > "$work/typed"
bin/codegen < "$work/typed" > "$work/ir"
pass 'standalone stages default successfully'

(
  cd src
  ../bin/lexer < argparse.pas > "$work/bootstrap.tokens"
  ../bin/parser < "$work/bootstrap.tokens" > "$work/bootstrap.ast"
)
status=0
bin/typechecker < "$work/bootstrap.ast" > "$work/bootstrap.typed" \
  2> "$work/bootstrap.err" || status=$?
if [ "$status" -ne 0 ] &&
   grep -qF 'Type requires the extended dialect: INTEGER32' \
     "$work/bootstrap.err"; then
  pass 'omitted bootstrap dialect rejects extended compiler source'
else
  fail 'omitted bootstrap dialect rejects extended compiler source'
  cat "$work/bootstrap.err" >&2
fi
if bin/typechecker --dialect extended < "$work/bootstrap.ast" \
     > "$work/bootstrap-extended.typed" 2> "$work/bootstrap-extended.err"; then
  pass 'explicit extended bootstrap dialect accepts compiler source'
else
  fail 'explicit extended bootstrap dialect accepts compiler source'
  cat "$work/bootstrap-extended.err" >&2
fi

for dialect in vintage extended; do
  bin/parser --dialect "$dialect" < "$work/tokens" > "$work/parser-$dialect"
  compare_output "$work/ast" "$work/parser-$dialect" \
    "parser accepts --dialect $dialect without changing its AST"

  bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typechecker-$dialect"
  compare_output "$work/typed" "$work/typechecker-$dialect" \
    "typechecker accepts --dialect $dialect"

  bin/codegen --dialect "$dialect" < "$work/typed" > "$work/codegen-$dialect"
  compare_output "$work/ir" "$work/codegen-$dialect" \
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
  "bin/$stage" --help > "$work/help" 2> "$work/help.err" || status=$?
  if [ "$status" -eq 0 ] && grep -qF -- '--dialect' "$work/help" && [ ! -s "$work/help.err" ]; then
    pass "$stage --help describes the dialect option"
  else
    fail "$stage --help describes the dialect option"
    cat "$work/help" >&2
    cat "$work/help.err" >&2
  fi
done

# The token JSON is a stage interface, so the parser must not narrow its
# integer fields to the dialect's 16-bit INTEGER. A LSTRING capacity past
# 32767 came out of TRUNC wrapped (40000 as -25536), and a column past 32767
# would be poison in the same way. The native lexer's own column counter
# wraps at 16 bits today, but that is the lexer's limitation, not the
# parser's contract -- both regressions are replayed straight into the
# stage's stdin here.
wide_cap_src="$work/wide_cap.pas"
cat > "$wide_cap_src" <<'EOF'
PROGRAM WideCap;
VAR s: LSTRING(40000);
BEGIN
END.
EOF
bin/lexer < "$wide_cap_src" > "$work/wide_cap.tokens"
if bin/parser < "$work/wide_cap.tokens" > "$work/wide_cap.ast" 2> "$work/wide_cap.err" \
   && grep -q '"param":[[:space:]]*40000' "$work/wide_cap.ast"; then
  pass 'parser keeps a STRING/LSTRING capacity past 16 bits intact'
else
  fail 'parser keeps a STRING/LSTRING capacity past 16 bits intact'
  cat "$work/wide_cap.err" >&2
fi
sed 's/"column":[[:space:]]*[0-9][0-9]*/"column":40000/g' \
  "$work/wide_cap.tokens" > "$work/wide_col.tokens"
# Columns reach the AST as source coordinates (read sites such as the body's
# closing END, an INITCK fallthrough-return site, and statement/declaration
# locations): they must carry 40000 exactly and leave everything else
# unchanged.
if bin/parser < "$work/wide_col.tokens" > "$work/wide_col.ast" 2> "$work/wide_col.err" \
   && python3 tests/contract/fixtures/stage_cli/wide-columns.py "$work/wide_cap.ast" "$work/wide_col.ast"
then
  pass 'parser accepts a column past 16 bits unchanged'
else
  fail 'parser accepts a column past 16 bits unchanged'
  cat "$work/wide_col.err" >&2
fi

finish "Stage CLI"
