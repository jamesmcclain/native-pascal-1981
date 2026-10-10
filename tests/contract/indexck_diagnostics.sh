#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# INDEXCK failures report the first index token, preserving bounds and side effects.
require bin/pascal1981 bin/lexer bin/parser bin/typechecker bin/codegen
for dialect in vintage extended; do
  for shape in fixed super; do
    array='ARRAY [-2..3]'; slot='a: A'; target='a'; setup='i := 4'
    if [[ $shape == super ]]; then
      array='SUPER ARRAY [-2..*]'; slot='p: ^A'; target='p^'; setup='NEW(p, 3); i := 4'
    fi
    for consumer in load store; do
      access="  WRITELN($target["
      tail='    next {$INDEXCK-}]);'
      if [[ $consumer == store ]]; then access="  $target["; tail='    next {$INDEXCK-}] := 7;'; fi
      printf '%s\n' 'PROGRAM checked;' "TYPE A = $array OF INTEGER;" \
        "VAR $slot; i: INTEGER;" 'FUNCTION next: INTEGER;' \
        'BEGIN WRITELN('\''index'\''); next := i END;' 'BEGIN' \
        "  $setup;" '  WRITELN('\''before'\'');' "$access" "$tail" \
        '  WRITELN('\''after'\'')' 'END.' > "$work/bad.pas"
      bin/lexer < "$work/bad.pas" | bin/parser --dialect "$dialect" > "$work/ast.json"
      jq -e '[.. | objects | select(.__node_type__? == "Selector" and .kind? == "INDEX") | .op_location] == [{line:10,column:5}]' \
        "$work/ast.json" >/dev/null || die "$dialect $shape $consumer index snapshot"
      printf 'before\nindex\n' > "$work/expected.out"
      printf 'runtime error: array index 4 is outside bounds -2..3 at line 10 column 5\n' > "$work/expected.err"
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/bad.pas" -o "$work/bad"
        rc=0
        { "$work/bad" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
        [[ $rc != 0 ]] || die "$dialect $shape $consumer O$opt did not fail"
        diff -u "$work/expected.out" "$work/output"
        diff -u "$work/expected.err" "$work/error"
        pass "$dialect $shape $consumer O$opt location and single evaluation"
      done
      # Legacy selectors remain checked by default, but have no invented
      # coordinates; mixed input must retain the supplied selector snapshot.
      bin/typechecker --dialect "$dialect" < "$work/ast.json" > "$work/typed.json"
      jq 'walk(if type == "object" and .__node_type__? == "Selector" and .kind? == "INDEX" then del(.op_location, .indexck) else . end)' \
        "$work/typed.json" > "$work/legacy.json"
      bin/codegen --dialect "$dialect" < "$work/legacy.json" > "$work/legacy.ll"
      grep -Eq 'call void @pas_array_index_error\(.*i32 0, i32 0\)' "$work/legacy.ll" || die 'legacy INDEXCK location/default'
      clang -O0 "$work/legacy.ll" runtime/build/libpascalrt.a -lcjson -lm -o "$work/legacy"
      rc=0
      { "$work/legacy" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
      [[ $rc != 0 ]] || die 'legacy INDEXCK did not fail'
      diff -u "$work/expected.out" "$work/output"
      printf 'runtime error: array index 4 is outside bounds -2..3 at line 0 column 0\n' > "$work/legacy.err"
      diff -u "$work/legacy.err" "$work/error"
      jq 'walk(if type == "object" and .__node_type__? == "Selector" and .kind? == "INDEX" then .op_location = {line:123,column:45} else . end)' \
        "$work/legacy.json" | bin/codegen --dialect "$dialect" > "$work/mixed.ll"
      grep -Eq 'call void @pas_array_index_error\(.*i32 123, i32 45\)' "$work/mixed.ll" || die 'mixed selector lost supplied coordinates'
      # No disabled invalid access is executed.
      jq 'walk(if type == "object" and .__node_type__? == "Selector" and .kind? == "INDEX" then .indexck = false else . end)' \
        "$work/typed.json" | bin/codegen --dialect "$dialect" > "$work/off.ll"
      ! grep -q 'pas_array_index_error' "$work/off.ll" || die 'disabled INDEXCK emitted bounds diagnostic'
      pass "$dialect $shape $consumer legacy and disabled IR"
    done
  done
  # A recursive index expression must diagnose the inner failing selector,
  # not overwrite/reuse the outer index's snapshot.
  printf '%s\n' 'PROGRAM nested;' 'VAR a, b: ARRAY [1..2] OF INTEGER; i: INTEGER;' \
    'BEGIN' '  i := 3;' '  WRITELN('\''before'\'');' '  WRITELN(a[' \
    '    b[' '      i]]);' 'END.' > "$work/nested.pas"
  bin/lexer < "$work/nested.pas" | bin/parser --dialect "$dialect" > "$work/nested.json"
  jq -e '[.. | objects | select(.__node_type__? == "Selector" and .kind? == "INDEX") | .op_location] == [{line:7,column:5},{line:8,column:7}]' \
    "$work/nested.json" >/dev/null || die 'nested index snapshots'
  for opt in 0 1 2 3; do
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/nested.pas" -o "$work/nested"
    rc=0
    { "$work/nested" > "$work/output" 2> "$work/error"; } 2>/dev/null || rc=$?
    [[ $rc != 0 ]] || die 'nested INDEXCK did not fail'
    printf 'before\n' > "$work/expected.out"
    printf 'runtime error: array index 3 is outside bounds 1..2 at line 8 column 7\n' > "$work/expected.err"
    diff -u "$work/expected.out" "$work/output"
    diff -u "$work/expected.err" "$work/error"
    pass "$dialect nested index O$opt"
  done
done
finish 'INDEXCK diagnostics'
