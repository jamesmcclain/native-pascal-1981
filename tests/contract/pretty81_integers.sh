#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 preserves exact INTEGER64 and upper-half WORD64 literals through parsed and typed ASTs.
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
# WORD64 literals of 2^63 and above travel as their bit pattern plus a
# word64 mark; pretty81 must print the unsigned spelling, and the negated
# 2^63 must come back as a signed literal that a CONST accepts.
golden=tests/corpus/golden/word64_literal_upper_half
bin/lexer < "$golden.pas" | bin/parser --dialect extended > "$work/w64.json"
bin/pretty81 < "$work/w64.json" > "$work/w64.pas"
bin/lexer < "$work/w64.pas" | bin/parser --dialect extended > "$work/w64re.json"
for ast in w64 w64re; do
  jq -c '[.. | objects | select(.__node_type__? == "IntLiteral") | [.value_int64, .word64]]' \
    "$work/$ast.json" > "$work/$ast.values"
done
grep -q true "$work/w64.values" || die 'WORD64 literals lost their word64 mark'
diff -u "$work/w64.values" "$work/w64re.values" || die 'WORD64 literal values changed'
grep -qF 'MIN64 = -9223372036854775808;' "$work/w64.pas" || die 'negated 2^63 spelling'
pass 'WORD64 exact round-trip'
bin/pascal1981 --dialect extended "$work/w64.pas" -o "$work/w64"
"$work/w64" > "$work/w64.out"
diff -u "$golden.out" "$work/w64.out" || die 'WORD64 round-trip runtime values changed'
pass 'WORD64 round-trip runtime values'
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
