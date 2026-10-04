#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INITCK metadata, legacy opt-out and boundary diagnostics; bad reads compile-only.
# Enabling a directive alone no longer warns. Unsupported consumers are
# rejected by codegen, not guessed from a lexer flag transition.
: > "$work/warning"
reject_boundary() {
  if bin/codegen < "$1" > "$2" 2> "$work/boundary.err"; then
    echo 'FAIL: unsupported checked read accepted' >&2; exit 1
  fi
  grep '^INITCK unsupported boundary:' "$work/boundary.err"
  test ! -s "$2"
}
(
  cd src
  "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/initck_metadata_check.pas \
    jsonutil.pas -o "$work/check"
)
cat > "$work/expected" <<'EXPECTED'
ck_default:FALSE
ck_on:TRUE
ck_off:FALSE
ck_debug:TRUE
ck_override:FALSE
ck_pushed:TRUE
ck_restored:FALSE
ck_if_off:FALSE
ck_if_on:TRUE
ck_debug_off:FALSE
ck_after_debug_off:TRUE
ck_mid:TRUE
ck_after_mid:FALSE
ck_last:TRUE
EXPECTED
bin/lexer < tests/contract/fixtures/initck_metadata.pas > "$work/tokens" 2> "$work/diagnostic"
diff -u "$work/warning" "$work/diagnostic"
bin/parser < "$work/tokens" > "$work/ast"
bin/typechecker < "$work/ast" > "$work/typed"
for stage in tokens ast typed; do
  "$work/check" < "$work/$stage" > "$work/actual"
  diff -u "$work/expected" "$work/actual"
done

# Read-site snapshots survive typechecking unchanged and reach codegen.
# Never execute this fixture: enabled global/selected reads are unsupported.
(
  cd src
  "$ROOT/bin/pascal1981" --dialect extended ../tests/contract/fixtures/initck_read_check.pas \
    jsonutil.pas -o "$work/read-check"
)
cat > "$work/read-expected" <<'EXPECTED'
Identifier:rs_x:TRUE
Identifier:rs_x:FALSE
Identifier:rs_x:FALSE
Designator:rs_a:TRUE
Selector:INDEX:FALSE
Identifier:rs_i:FALSE
Identifier:rs_x:TRUE
Designator:rs_p:FALSE
Selector:DEREF:TRUE
Designator:rs_p:TRUE
Selector:DEREF:FALSE
UpperExpr::TRUE
Identifier:rs_a:FALSE
FuncCall:ORD:TRUE
Identifier:rs_x:FALSE
EXPECTED
bin/lexer < tests/contract/fixtures/initck_reads.pas > "$work/read-tokens" 2> "$work/diagnostic"
diff -u "$work/warning" "$work/diagnostic"
bin/parser < "$work/read-tokens" > "$work/read-ast"
bin/typechecker < "$work/read-ast" > "$work/read-typed"
for stage in ast typed; do
  "$work/read-check" < "$work/read-$stage" > "$work/actual"
  diff -u "$work/read-expected" "$work/actual"
done
reject_boundary "$work/read-typed" "$work/read.ll"

# Declaration/use differences for globals and routine locals, repeated uses of
# the same slot within a statement, and toggles after an emitted identifier.
# Keep declaration and read oracles separate: neither may substitute for the other.
cat > "$work/toggle-decl-expected" <<'EXPECTED'
rs_global_on:TRUE
rs_global_off:FALSE
rs_local_on:TRUE
rs_local_off:FALSE
EXPECTED
cat > "$work/toggle-read-expected" <<'EXPECTED'
Identifier:rs_global_off:TRUE
Identifier:rs_global_off:FALSE
Identifier:rs_global_on:FALSE
Identifier:rs_global_on:TRUE
Identifier:rs_local_off:TRUE
Identifier:rs_local_off:FALSE
Identifier:rs_local_on:FALSE
Identifier:rs_local_on:TRUE
Designator:rs_local_off:FALSE
Identifier:rs_local_on:TRUE
Identifier:rs_global_on:FALSE
Identifier:rs_local_off:TRUE
Identifier:rs_local_on:FALSE
Identifier:rs_global_off:TRUE
FuncCall:ORD:FALSE
Identifier:rs_local_off:TRUE
Identifier:rs_local_on:FALSE
EXPECTED
bin/lexer < tests/contract/fixtures/initck_read_toggles.pas > "$work/toggle-tokens" 2> "$work/diagnostic"
diff -u "$work/warning" "$work/diagnostic"
bin/parser < "$work/toggle-tokens" > "$work/toggle-ast"
bin/typechecker < "$work/toggle-ast" > "$work/toggle-typed"
for stage in ast typed; do
  "$work/check" < "$work/toggle-$stage" > "$work/actual"
  diff -u "$work/toggle-decl-expected" "$work/actual"
  "$work/read-check" < "$work/toggle-$stage" > "$work/actual"
  diff -u "$work/toggle-read-expected" "$work/actual"
done
reject_boundary "$work/toggle-typed" "$work/toggle.ll"

# Actual consumers under DEBUG/override, nested PUSH/POP, active/skipped
# conditionals and includes. Distinct names make omitted/leaked reads visible.
cat > "$work/transition-read-expected" <<'EXPECTED'
Identifier:rs_debug_on:TRUE
Identifier:rs_override_off:FALSE
Identifier:rs_debug_recoupled:TRUE
Identifier:rs_debug_off:FALSE
Identifier:rs_override_on:TRUE
Identifier:rs_push_outer:TRUE
Identifier:rs_push_inner:FALSE
Identifier:rs_pop_inner:TRUE
Identifier:rs_pop_outer:FALSE
Identifier:rs_if_off:FALSE
Identifier:rs_if_on:TRUE
Identifier:rs_after_skipped:TRUE
Identifier:rs_include_on:TRUE
Identifier:rs_include_after:TRUE
Identifier:rs_include_off:FALSE
Identifier:rs_include_restored:TRUE
Identifier:rs_include_pop:FALSE
Identifier:rs_emitted:FALSE
Identifier:rs_next:TRUE
EXPECTED
bin/lexer < tests/contract/fixtures/initck_read_transitions.pas > "$work/transition-tokens" 2> "$work/diagnostic"
diff -u "$work/warning" "$work/diagnostic"
bin/parser < "$work/transition-tokens" > "$work/transition-ast"
bin/typechecker < "$work/transition-ast" > "$work/transition-typed"
for stage in ast typed; do
  "$work/read-check" < "$work/transition-$stage" > "$work/actual"
  diff -u "$work/transition-read-expected" "$work/actual"
done
reject_boundary "$work/transition-typed" "$work/transition.ll"

# Legacy ASTs opt out per node: never infer snapshots from declarations,
# statements, or neighboring consumers. Exercise both parser and typed inputs.
# These are compile-only probes, not initialization-safety tests.
for stage in ast typed; do
  for mode in legacy mixed; do
    python3 tests/contract/fixtures/initck_contract/strip-read-flags.py "$work/read-$stage" "$work/$mode-$stage" "$mode"
    bin/typechecker < "$work/$mode-$stage" > "$work/$mode-$stage-typed"
    python3 tests/contract/fixtures/initck_contract/read-provenance.py "$work/$mode-$stage" "$work/$mode-$stage-typed" "$mode"
    # In this alternating fixture the retained true snapshots are on
    # non-consuming nodes; no enabled unsupported storage read remains.
    bin/codegen < "$work/$mode-$stage-typed" > "$work/$mode-$stage.ll"
    ! grep -q 'pas_initck_error' "$work/$mode-$stage.ll"
    diff -u "$work/legacy-$stage.ll" "$work/$mode-$stage.ll"
  done
done

# Enabling directly, numerically, implicitly, or through DEBUG alone is silent.
# Skipped branches and repeated enablement must remain silent too.
for directive in '{$INITCK+}' '{$INITCK:1}' '{$INITCK}' '{$DEBUG+}' \
  '{$WARN-,INITCK+}' '{$INITCK+,INITCK-,DEBUG+,INITCK+}'; do
  printf '%s\nPROGRAM probe; BEGIN END.\n' "$directive" |
    bin/lexer > "$work/tokens" 2> "$work/diagnostic"
  diff -u "$work/warning" "$work/diagnostic"
done
for directive in '' '{$INITCK-}' '{$DEBUG-}' '{$INITCK:0}' \
  '{$IF 0 $THEN}{$INITCK+,DEBUG+}{$END}'; do
  printf '%s\nPROGRAM probe; BEGIN END.\n' "$directive" |
    bin/lexer > "$work/tokens" 2> "$work/diagnostic"
  test ! -s "$work/diagnostic"
done

# Includes without unsupported consumers do not warn either.
printf '%s\n' '{$INITCK+}' > "$work/enable.inc"
printf '%s\n' "{\$INCLUDE:'$work/enable.inc'}" '{$DEBUG+}' \
  'PROGRAM probe; BEGIN END.' |
  bin/lexer > "$work/tokens" 2> "$work/diagnostic"
diff -u "$work/warning" "$work/diagnostic"

# Missing or non-boolean metadata must fail, not silently become FALSE.
for flags in '{}' '{"INITCK":0}'; do
  printf '[{"kind":"IDENTIFIER","lexeme":"ck_bad","flags":%s}]\n' "$flags" |
    "$work/check" > "$work/actual" 2> "$work/diagnostic" && {
      echo 'FAIL: invalid INITCK snapshot accepted' >&2
      exit 1
    }
  grep -Fx 'missing or non-boolean INITCK snapshot' "$work/diagnostic" > /dev/null
done

# Public driver inserts enabled guards but never guards disabled probes.
# Never execute the disabled uninitialized read.
for mode in on off; do
  directive='{$INITCK-}'
  if [ "$mode" = on ]; then directive='{$INITCK+}'; fi
  printf '%s\nPROGRAM initprobe;\nPROCEDURE probe;\nVAR x: INTEGER;\nBEGIN WRITELN(x) END;\nBEGIN probe END.\n' \
    "$directive" > "$work/$mode.pas"
  bin/pascal1981 "$work/$mode.pas" -O0 -S -o "$work/$mode.ll" 2> "$work/diagnostic"
  if [ "$mode" = on ]; then
    diff -u "$work/warning" "$work/diagnostic"
  else
    test ! -s "$work/diagnostic"
  fi
done
grep -q 'call void @pas_initck_error' "$work/on.ll"
! grep -q 'pas_initck_error' "$work/off.ll"
diff -u "$work/legacy-ast.ll" "$work/legacy-typed.ll"
# Public-driver warning replacement gate: unsupported declarations and writes
# are silent; multiple enabled unsupported reads fail fast with just the first
# located boundary, never a directive warning flood. All probes compile only.
cp tests/contract/fixtures/initck_contract/boundary-gate.pas "$work/boundary-gate.pas"
sed '/WRITELN/d' "$work/boundary-gate.pas" > "$work/boundary-writes.pas"
sed 's/INITCK+/INITCK-/g; s/DEBUG+/DEBUG-/g' \
  "$work/boundary-gate.pas" > "$work/boundary-off.pas"
printf '%s\n' 'INITCK unsupported boundary: global or captured storage at line 9 column 11' \
  > "$work/boundary-expected"
for dialect in vintage extended; do
  for opt in 0 2; do
    for probe in boundary-writes boundary-off; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" -S \
        "$work/$probe.pas" -o "$work/$probe.ll" 2> "$work/diagnostic"
      test ! -s "$work/diagnostic"
      test -s "$work/$probe.ll"
    done
    rm -f "$work/boundary-gate.ll"
    if bin/pascal1981 --dialect "$dialect" -O"$opt" -S \
      "$work/boundary-gate.pas" -o "$work/boundary-gate.ll" 2> "$work/diagnostic"; then
      echo 'FAIL: public driver accepted unsupported checked reads' >&2; exit 1
    fi
    diff -u "$work/boundary-expected" "$work/diagnostic"
    test ! -s "$work/boundary-gate.ll"
  done
done
echo 'PASS: INITCK snapshots, legacy opt-out, coupling/restoration and boundary rejection'
