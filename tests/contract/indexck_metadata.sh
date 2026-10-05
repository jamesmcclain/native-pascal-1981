#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Verify native per-index metadata without Python or unchecked bad accesses.
(
  cd src
  "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/indexck_metadata_check.pas \
    jsonutil.pas -o "$work/check"
)
# Source order: default store; RANGECK-independent store/load; disabled load;
# nested indexes; comma/repeated dimensions; call; IF; WHILE; REPEAT; FOR;
# WITH; pointer; PUSH/POP; directive after the first token; subsequent index.
printf '%s\n' TRUE TRUE FALSE FALSE TRUE FALSE \
  TRUE FALSE TRUE FALSE TRUE FALSE TRUE FALSE TRUE FALSE TRUE FALSE \
  TRUE FALSE TRUE FALSE TRUE FALSE TRUE TRUE FALSE > "$work/expected"
bin/lexer < tests/contract/fixtures/indexck_metadata.pas | bin/parser > "$work/ast"
bin/typechecker < "$work/ast" > "$work/typed"
for stage in ast typed; do
  "$work/check" < "$work/$stage" > "$work/actual"
  diff -u "$work/expected" "$work/actual"
done
# Compile only: the fixture intentionally contains uninitialized values and
# a pointer. No program execution (and no runtime guards in this slice).
bin/codegen < "$work/typed" > "$work/module.ll"
# Legacy AST input without selector snapshots must still compile.
bin/codegen < tests/corpus/reference/ast/with_stmt.typed.json > "$work/legacy.ll"
echo 'PASS: per-index INDEXCK snapshots survive parser/typechecker/codegen'
