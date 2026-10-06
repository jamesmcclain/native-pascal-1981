#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 preserves exact signed INTEGER64 literals through parsed and typed ASTs.
require bin/pretty81 bin/lexer bin/parser bin/typechecker bin/pascal1981
command -v jq >/dev/null || die 'jq is required'
printf '%s\n' 'PROGRAM wide;' 'VAR x: INTEGER64;' 'BEGIN' \
  '  x := 0; WRITELN(x);' '  x := 2147483647; WRITELN(x);' \
  '  x := -2147483648; WRITELN(x);' '  x := 2147483648; WRITELN(x);' \
  '  x := -2147483649; WRITELN(x);' '  x := 4294967295; WRITELN(x);' \
  '  x := 5000000000; WRITELN(x);' '  x := 9007199254740993; WRITELN(x);' \
  '  x := 9223372036854775805; WRITELN(x);' \
  '  x := 9223372036854775807; WRITELN(x);' \
  '  x := -9223372036854775807; WRITELN(x)' 'END.' > "$work/wide.pas"
printf '%s\n' 0 2147483647 -2147483648 2147483648 -2147483649 4294967295 \
  5000000000 9007199254740993 9223372036854775805 9223372036854775807 \
  -9223372036854775807 > "$work/expected"
# Vintage has no wide types; it still must round-trip parsed numeric values.
for dialect in vintage extended; do
  bin/lexer < "$work/wide.pas" | bin/parser --dialect "$dialect" > "$work/parsed.json"
  stages=parsed
  if [[ $dialect == extended ]]; then
    bin/typechecker --dialect extended < "$work/parsed.json" > "$work/typed.json"
    stages='parsed typed'
  fi
  for stage in $stages; do
    bin/pretty81 < "$work/$stage.json" > "$work/pretty.pas"
    bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/reparsed.json"
    for ast in "$stage" reparsed; do
      jq -c '[.. | objects | select(.__node_type__? == "IntLiteral") | [.value, .value_int64]]' \
        "$work/$ast.json" > "$work/$ast.values"
    done
    diff -u "$work/$stage.values" "$work/reparsed.values" || die "$dialect $stage integer values changed"
    bin/pretty81 < "$work/reparsed.json" > "$work/again.pas"
    diff -u "$work/pretty.pas" "$work/again.pas" || die "$dialect $stage not idempotent"
    pass "$dialect $stage exact/idempotent round-trip"
    if [[ $dialect == extended ]]; then
      for opt in 0 1 2 3; do
        bin/pascal1981 --dialect extended -O"$opt" "$work/pretty.pas" -o "$work/wide"
        "$work/wide" > "$work/actual"
        diff -u "$work/expected" "$work/actual" || die "$stage O$opt runtime values changed"
        pass "$stage O$opt runtime values"
      done
    fi
  done
done
# Legacy/exact JSON can contain a negative IntLiteral directly. Exercise the
# formatter's full signed domain, including MIN64, without negating its magnitude.
printf '%s\n' 'PROGRAM edge; BEGIN WRITELN(0) END.' | bin/lexer | bin/parser > "$work/edge.json"
for value in -2147483648 -9223372036854775808; do
  jq --arg v "$value" 'walk(if type == "object" and .__node_type__? == "IntLiteral" then .value = 0 | .value_int64 = $v else . end)' \
    "$work/edge.json" > "$work/exact.json"
  bin/pretty81 < "$work/exact.json" > "$work/edge.pas"
  grep -qF "WRITELN($value)" "$work/edge.pas" || die "direct $value formatting"
  pass "direct $value formatting"
done
finish 'pretty81 integers'
