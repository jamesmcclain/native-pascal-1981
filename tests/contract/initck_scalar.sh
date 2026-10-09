#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INITCK producers and guards for scalar locals.
#
# Direct scalar-local producer/guard matrix. Never run unchecked bad reads.
cp tests/contract/fixtures/initck_scalar/good.pas "$work/good.pas"
printf '0\n-32768\n8\n11\n13\n2a\n1a\n0a\n1a\n0a\n2\n2\n3\n2\n2\n3\n' > "$work/expected"
# Keep the extra trailing newline emitted by the former Python print.
{
  sed -e 's/{$INITCK+}/{$INITCK-}/g' -e 's/{$DEBUG+}/{$DEBUG-}/g' "$work/good.pas"
  printf '\n'
} > "$work/good-off.pas"
for dialect in vintage extended; do
  for mode in good good-off; do
    for opt in 0 2; do
      bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/$mode.pas" -o "$work/good" 2> "$work/err"
      test ! -s "$work/err"
      "$work/good" > "$work/actual" 2> "$work/err"
      diff -u "$work/expected" "$work/actual"
      test ! -s "$work/err"
    done
  done
done
# Disabled producers remain producers: all supported types, both taken paths,
# an unchecked initialized RHS/copy, and overwrites after a checked read.
# Declare under INITCK+ so neither declaration nor producer flags can stand in
# for the actual consumer snapshot. Parameter reads occur only under INITCK-.
cp tests/contract/fixtures/initck_scalar/disabled-writes.pas "$work/disabled-writes.pas"
printf '0:0:0:a\n1:1:1:q\n-32768:-32768:1:z\n-32767:-32767:0:q\n0:0:0:a\n1:1:1:q\n' > "$work/expected-disabled"
for dialect in vintage extended; do
  for opt in 0 2; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/disabled-writes.pas" -o "$work/disabled-writes" 2> "$work/err"
    test ! -s "$work/err"
    "$work/disabled-writes" > "$work/actual" 2> "$work/err"
    diff -u "$work/expected-disabled" "$work/actual"
    test ! -s "$work/err"
  done
done
# Negative expression, condition, skipped writer, and fresh recursive activation.
for kind in expression selfupdate condition character skipped disabledskipped recursion conditional earlyreturn repeat restored debug; do
  case "$kind" in
    expression) decl='x: INTEGER'; body='WRITELN(x + 1)' ;;
    selfupdate) decl='x: INTEGER'; body='x := x + 1; WRITELN(x)' ;;
    condition) decl='x: BOOLEAN'; body="IF x THEN WRITELN('bad')" ;;
    character) decl='x: CHAR'; body='WRITELN(x)' ;;
    skipped) decl='x: INTEGER'; body='WHILE FALSE DO x := 1; WRITELN(x)' ;;
    disabledskipped) decl='x: INTEGER'; body='{$INITCK-} WHILE FALSE DO x := 1; {$INITCK+} WRITELN(x)' ;;
    recursion) decl='x: INTEGER'; body='IF n > 0 THEN x := 1; IF n > 0 THEN probe(n - 1); {$INITCK+} WRITELN(x)' ;;
    conditional) decl='x: INTEGER'; body='IF FALSE THEN x := 1; WRITELN(x)' ;;
    earlyreturn) decl='x: INTEGER'; body='{$INITCK-} IF n > 0 THEN BEGIN x := 1; probe(0); RETURN END; {$INITCK+} WRITELN(x)' ;;
    repeat) decl='x: INTEGER'; body='REPEAT WRITELN(x); x := 1 UNTIL TRUE' ;;
    restored) decl='x: INTEGER'; body='{$PUSH} {$INITCK-} IF FALSE THEN x := 1; {$POP} WRITELN(x)' ;;
    debug) decl='x: INTEGER'; body='{$DEBUG-} {$DEBUG+} WRITELN(x)' ;;
  esac
  cat > "$work/bad.pas" <<PAS
PROGRAM bad;
PROCEDURE probe(n: INTEGER);
VAR $decl;
BEGIN
  WRITELN('prefix');
  $(if [ "$kind" != recursion ]; then echo '{$INITCK+}'; fi)
  $body;
  WRITELN('after')
  {\$INITCK-}
END;
BEGIN probe(1) END.
PAS
  for opt in 0 2; do
    bin/pascal1981 -O"$opt" "$work/bad.pas" -o "$work/bad" 2> "$work/err"
    test ! -s "$work/err"
    status=0
    { "$work/bad" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    # ASCII body at line 7, with two indentation spaces. Self-update skips
    # the destination; REPEAT consumes the first x; other cases use the last.
    printf '%s\n' "$body" | LC_ALL=C awk -v kind="$kind" '
      {
        if (kind == "selfupdate") {
          column = index(substr($0, 2), "x")
          if (column) column++
        } else if (kind == "repeat") {
          column = index($0, "x")
        } else {
          for (column = length($0); column > 0; column--)
            if (substr($0, column, 1) == "x") break
        }
        if (!column) exit 1
        printf "runtime error: INITCK uninitialized local x at line 7 column %d\n", column + 2
      }
    ' > "$work/expected-err"
    diff -u "$work/expected-err" "$work/err"
    printf 'prefix\n' > "$work/expected-bad"
    if [ "$kind" = recursion ] || [ "$kind" = earlyreturn ]; then
      printf 'prefix\n' >> "$work/expected-bad"
    fi
    diff -u "$work/expected-bad" "$work/actual"
  done
done
# Parentheses retain the identifier's source position, not the opening paren.
# Explicit checked legacy ASTs without coordinates still fail by local name.
cp tests/contract/fixtures/initck_scalar/context.pas "$work/context.pas"
bin/lexer < "$work/context.pas" | bin/parser > "$work/context-parser.json"
bin/typechecker < "$work/context-parser.json" > "$work/context-typed.json"
python3 tests/contract/fixtures/initck_scalar/read-locations.py "$work/context-parser.json" "$work/context-typed.json" "$work/no-location.json" "$work/designator.json"
bin/codegen < "$work/no-location.json" > "$work/no-location.ll"
bin/codegen < "$work/designator.json" > "$work/designator.ll"
for opt in 0 2; do
  bin/pascal1981 -O"$opt" "$work/context.pas" -o "$work/context"
  clang -O"$opt" "$work/no-location.ll" runtime/build/libpascalrt.a -lm -o "$work/no-location"
  clang -O"$opt" "$work/designator.ll" runtime/build/libpascalrt.a -lm -o "$work/designator"
  for mode in context designator no-location; do
    status=0
    { "$work/$mode" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
    test "$status" -ne 0
    test ! -s "$work/actual"
    if [ "$mode" != no-location ]; then
      printf 'runtime error: INITCK uninitialized local unset at line 6 column 12\n'
    else
      printf 'runtime error: INITCK uninitialized local unset\n'
    fi > "$work/expected-err"
    diff -u "$work/expected-err" "$work/err"
  done
done
# Diagnostic classes remain independent. NIL here is the existing SUPER
# runtime error, not a claim that the NILCK directive has been implemented.
cat > "$work/classes.c" <<'C'
#include "pascalrt.h"
int main(int argc, char **argv) {
    if (argv[1][0] == 'i') pas_initck_error("slot", 23, 9);
    if (argv[1][0] == 'n') pas_super_index_nil_error();
    pas_array_index_error(3, 0, 1, 2, 23, 9);
}
C
clang -I runtime "$work/classes.c" runtime/build/libpascalrt.a -lm -o "$work/classes"
for mode in initck nil bounds; do
  status=0
  { "$work/classes" "$mode" > "$work/actual" 2> "$work/err"; } 2>/dev/null || status=$?
  test "$status" -ne 0
  test ! -s "$work/actual"
  case "$mode" in
    initck) printf 'runtime error: INITCK uninitialized local slot at line 23 column 9\n' ;;
    nil) printf 'runtime error: index through NIL super-array pointer\n' ;;
    bounds) printf 'runtime error: array index 3 is outside bounds 1..2 at line 23 column 9\n' ;;
  esac > "$work/expected-err"
  diff -u "$work/expected-err" "$work/err"
done
# O0 ordering, exact scalar types, successful-store publication, and no disabled guard.
cp tests/contract/fixtures/initck_scalar/order.pas "$work/order.pas"
bin/pascal1981 -O0 -S "$work/order.pas" -o "$work/order.ll"
python3 tests/contract/fixtures/initck_scalar/order.py "$work/order.ll"
# Unwritten disabled read: compile ONLY. Legacy snapshots cannot enable guards.
cp tests/contract/fixtures/initck_scalar/off.pas "$work/off.pas"
bin/pascal1981 -O0 -S "$work/off.pas" -o "$work/off.ll"
! grep -q 'pas_initck_error' "$work/off.ll"
bin/lexer < "$work/order.pas" | bin/parser | bin/typechecker > "$work/order.json"
python3 tests/contract/fixtures/initck_scalar/strip-read-flags.py "$work/order.json" > "$work/legacy.json"
bin/codegen < "$work/legacy.json" > "$work/legacy.ll"
! grep -q 'pas_initck_error' "$work/legacy.ll"
# Taking/binding an address, naming input storage, and static type queries
# impose no old-content obligation, even for uninitialized/excluded storage.
# Compile only: this fixture would wait for input if run.
cp tests/contract/fixtures/initck_scalar/nonread.pas "$work/nonread.pas"
bin/pascal1981 -O0 -S "$work/nonread.pas" -o "$work/nonread.ll" 2> "$work/err"
test ! -s "$work/err"
! grep -q 'pas_initck_error' "$work/nonread.ll"
# Reject unsupported consumers with an exact, single category diagnostic.
# Whole-routine exclusion must see late/disabled/unreachable escapes. Every
# source is also compiled with reads disabled, so a syntax/type error cannot
# masquerade as boundary coverage. Neither version is executed.
# READ/READLN destinations and FOR control are producers (initck_producers.sh).
# Value and VAR/CONST formals, Pascal calls and tracked results are
# routine-boundary producers/consumers (initck_routines.sh). VAR/CONST
# actuals of [C] routines and ADR of a local or formal initialize the bound
# storage, and ADRMEM values are tracked leaves (initck_external.sh).
# Same-name nested locals and locals inside WITH bodies are supported
# (initck_routines.sh); a WITH whose target type is not evident stays conservative.
for kind in global real enum subrange heapreal globalptr realarray realfield withadr filereal string set with withunknown realresult realreturn builtin device; do
  header=''; local='x: INTEGER'; setup='x := 1'; expr='x'; after=''
  category='untracked type'
  case "$kind" in
    global) header='VAR g: INTEGER;'; expr='g'; category='global or captured storage' ;;
    real) local='x: REAL'; setup='x := 1.0' ;;
    enum) header='TYPE E = (red, blue);'; local='x: E'; setup='x := red' ;;
    subrange) local='x: 0..9' ;;
    # A plain typed pointer is a tracked leaf (initck_heap.sh); a heap
    # referent outside the tracked slice is not.
    heapreal) local='x: ^REAL'; setup='NEW(x); x^ := 1.0'; expr='x^:3:1'; category='heap storage' ;;
    # Reading a pointer to reach its referent is a read of the pointer.
    globalptr) header='VAR g: ^INTEGER;'; expr='1'; after='{$INITCK+} g^ := 1 {$INITCK-}'; category='global or captured storage' ;;
    # Tracked INTEGER/BOOLEAN/CHAR aggregates are covered by
    # initck_aggregates.sh; any other leaf leaves the whole object untracked.
    realarray) local='x: ARRAY [1..2] OF REAL'; setup='x[1] := 1.0'; expr='x[1]' ;;
    realfield) header='TYPE R = RECORD f: INTEGER; r: REAL END;'; local='x: R'; setup='x.f := 1'; expr='x.f' ;;
    # The address of a WITH-bound field escapes (raw writes from it may reach
    # its siblings), disqualifying the whole object.
    # A file buffer whose component type is outside the tracked slice.
    filereal) local='x: FILE OF REAL'; setup='REWRITE(x); x^ := 1.0'; expr='x^:3:1'; category='file buffer' ;;
    withadr) header='TYPE R = RECORD f, g: INTEGER END;'; local='x: R; p: ADRMEM'
      setup='x.f := 1'; expr='x.f'; after='WITH x DO p := ADR f'; category='escaped local or formal' ;;
    string) local='x: LSTRING(4)'; setup="x := 'ok'" ;;
    set) local='x: SET OF 0..9'; setup='x := [1]'; expr='1 IN x' ;;
    # Fields of an untracked record bound by WITH are untracked storage.
    with) header='TYPE R = RECORD f: INTEGER; r: REAL END;'; local='x: R'; setup='x.f := 1'; expr='1'; after='WITH x DO BEGIN {$INITCK+} WRITELN(f); {$INITCK-} END'
      category='untracked WITH target' ;;
    withunknown) # A WITH nested in another has targets whose fields are not
      # evident before lowering (the inner target may be an outer field).
      header='TYPE R = RECORD f: INTEGER END;'; local='x: INTEGER; a: ARRAY [1..1] OF R'
      after='WITH a[1] DO WITH a[1] DO x := 2'; category='escaped local or formal' ;;
    realresult|realreturn) category='function result' ;;
    builtin) expr='PRED(x)'; category='call consumer' ;;
    device) header='DEVICE;'; category='DEVICE code' ;;
  esac
  if [ "$kind" = device ]; then
    # Unlike the external DEVICE probe, keep INITCK enabled at closing END.
    cp tests/contract/fixtures/initck_scalar_device_read.pas "$work/boundary.pas"
    # Preserve the former generator's extra print newline.
    printf '\n' >> "$work/boundary.pas"
  elif [ "$kind" = realresult ]; then
    # An enabled closing END reads a result outside the tracked types.
    cp tests/contract/fixtures/initck_scalar/boundary.pas "$work/boundary.pas"
  elif [ "$kind" = realreturn ]; then
    cp tests/contract/fixtures/initck_scalar/boundary_2.pas "$work/boundary.pas"
  else
    cat > "$work/boundary.pas" <<PAS
PROGRAM boundary;
$header
PROCEDURE probe(n: INTEGER);
VAR $local;
BEGIN $setup; {\$INITCK+} WRITELN($expr); {\$INITCK-} $after END;
BEGIN probe(0) END.
PAS
  fi
  # Keep the extra trailing newline emitted by the former Python print.
  {
    sed 's/{$INITCK+}/{$INITCK-}/g' "$work/boundary.pas"
    printf '\n'
  } > "$work/boundary-off.pas"
  bin/pascal1981 --dialect extended -O0 -S "$work/boundary-off.pas" -o "$work/boundary-off.ll" 2> "$work/err"
  test ! -s "$work/err"
  for opt in 0 2; do
    rm -f "$work/boundary.ll"
    if bin/pascal1981 --dialect extended -O"$opt" -S "$work/boundary.pas" -o "$work/boundary.ll" 2> "$work/err"; then
      echo "FAIL: $kind boundary accepted" >&2; exit 1
    fi
    printf 'INITCK unsupported boundary: %s\n' "$category" > "$work/expected-err"
    # Locations are pinned per category in initck_external.sh.
    sed -E 's/ at line [0-9]+ column [0-9]+$//' "$work/err" | diff -u "$work/expected-err" -
    test ! -s "$work/boundary.ll"
  done
done
echo 'PASS: INITCK direct scalar-local writes, guarded reads, O0/O2 failures and boundaries'
