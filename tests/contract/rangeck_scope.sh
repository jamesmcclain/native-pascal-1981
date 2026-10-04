#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# RANGECK settings reach the AST and IR of FOR, CASE and SUCC where they apply.
(cd src; "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/rangeck_metadata_check.pas jsonutil.pas -o "$work/check")
printf '%s\n' 'ForStmt TRUE' 'CaseStmt TRUE' 'SUCC TRUE' 'SUCC FALSE' 'IDENTITY TRUE' 'IDENTITY FALSE' 'ForStmt TRUE' 'ForStmt FALSE' > "$work/metadata.expected"
printf '%s\n' 1 2 yes yes call off 1 2 1 2 > "$work/runtime.expected"
for dialect in vintage extended; do
  bin/lexer < tests/contract/fixtures/rangeck_scope.pas | bin/parser --dialect "$dialect" > "$work/ast"
  bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typed"
  for stage in ast typed; do
    "$work/check" < "$work/$stage" > "$work/metadata"
    diff -u "$work/metadata.expected" "$work/metadata"
  done
  bin/codegen < "$work/typed" > "$work/scope.ll"
  # Two checked FORs (four endpoints), one checked SUCC and one checked
  # value actual. Disabled siblings must not contribute guards.
  test "$(grep -c 'call void @pas_subrange_error' "$work/scope.ll")" = 6
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" tests/contract/fixtures/rangeck_scope.pas -o "$work/scope"
    "$work/scope" > "$work/output"
    diff -u "$work/runtime.expected" "$work/output"
  done
  # Contrast both preceding-statement settings against both FOR settings.
  for prior in + -; do
    for site in + -; do
      printf '%s\n' 'PROGRAM contrast; TYPE small = 1..2; VAR i: small; x: INTEGER;' \
        "BEGIN {\$RANGECK$prior} x := 0; {\$RANGECK$site} FOR i := 1 TO 2 DO WRITELN(i) END." > "$work/contrast.pas"
      bin/pascal1981 --dialect "$dialect" -S "$work/contrast.pas" -o "$work/contrast.ll"
      count=$(grep -c 'call void @pas_subrange_error' "$work/contrast.ll" || true)
      if [[ $site == + ]]; then test "$count" = 2; else test "$count" = 0; fi
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/contrast.pas" -o "$work/contrast"
        "$work/contrast" > "$work/output"
        printf '1\n2\n' > "$work/contrast.expected"
        diff -u "$work/contrast.expected" "$work/output"
      done
    done
  done
  # An admitted invalid checked endpoint must still fail, even after an
  # unchecked sibling. Never execute an invalid unchecked loop.
  printf '%s\n' 'PROGRAM bad; TYPE small = 1..2; VAR i: small; x: INTEGER;' \
    'BEGIN {$RANGECK-} x := 0; {$RANGECK+} FOR i := 1 TO 3 DO WRITELN(i) END.' > "$work/bad.pas"
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
    if "$work/bad" > "$work/output" 2> "$work/error"; then
      echo 'FAIL: checked FOR endpoint admitted at runtime' >&2; exit 1
    fi
    grep -qi 'subrange' "$work/error"
    test ! -s "$work/output"
  done
done
# Older typed ASTs lacking new snapshots still inherit a scoped context.
for name in enum_types forward_decl with_stmt; do
  bin/codegen < "tests/corpus/reference/ast/$name.typed.json" > "$work/legacy.ll"
done
echo 'PASS: scoped RANGECK snapshots, CASE/FOR tokens, nested actuals and sibling independence'
