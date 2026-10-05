#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Verify per-operation MATHCK snapshots survive parser/typechecker/codegen.
(
  cd src
  "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/mathck_metadata_check.pas \
    jsonutil.pas -o "$work/check"
)
fixtures=tests/contract/fixtures/mathck
# CONST intrinsic calls need the extended-const-intrinsics feature.
cells="vintage:metadata_ops vintage:metadata_builtins vintage:metadata_transitions
  extended:metadata_ops extended:metadata_builtins extended:metadata_transitions
  extended:metadata_const"
for cell in $cells; do
  dialect=${cell%%:*}
  name=${cell#*:}
  bin/lexer < "$fixtures/$name.pas" | bin/parser --dialect "$dialect" > "$work/ast"
  bin/typechecker --dialect "$dialect" < "$work/ast" > "$work/typed"
  for stage in ast typed; do
    "$work/check" < "$work/$stage" > "$work/actual"
    diff -u "$fixtures/$name.out" "$work/actual"
  done
  # Compile only here: codegen consumes snapshots; focused arithmetic suites
  # check their runtime effects. This suite checks metadata acceptance.
  bin/codegen < "$work/typed" > "$work/module.ll"
done
# Legacy typed ASTs without snapshots (frozen references with arithmetic)
# must still compile; their diagnostics use 0:0, checked in IR by
# mathck_divmod_safety.sh.
for name in enum_types forward_decl with_stmt; do
  if "$work/check" < "tests/corpus/reference/ast/$name.typed.json" > /dev/null 2>&1; then
    echo "frozen $name.typed.json unexpectedly carries MATHCK snapshots" >&2
    exit 1
  fi
  bin/codegen < "tests/corpus/reference/ast/$name.typed.json" > "$work/legacy.ll"
done
echo 'PASS: per-operation MATHCK snapshots survive parser/typechecker/codegen'
