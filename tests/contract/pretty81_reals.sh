#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 prints REAL literals that parse back to the identical double, with an E exponent where needed.
# -0.0 and a signed CONST name (-NZERO) keep their sign through every stage.
require bin/pretty81 bin/lexer bin/parser bin/typechecker bin/pascal1981
command -v jq >/dev/null || die 'jq is required'
printf '%s\n' 'PROGRAM reals(OUTPUT);' \
  'CONST NEG = -2.5; NMAX = -1.7976931348623157E308; NZERO = -0.0; NNEG = -NZERO;' \
  'VAR x: REAL;' 'BEGIN' \
  '  x := 0.1; WRITELN(x = 0.1);' \
  '  x := 0.30000000000000004; WRITELN(x = 0.1 + 0.2);' \
  '  x := 1.7976931348623157E308; WRITELN(x > 1.7976931348623155E308);' \
  '  x := 2.2250738585072014E-308; WRITELN(x / 2.0 > 0.0);' \
  '  x := 5.0E-324; WRITELN(x / 2.0 = 0.0);' \
  '  x := 12345678901234567890123.5; WRITELN(x:26:1);' \
  '  x := 99999999999999999999.0; WRITELN(x > 9.0E19);' \
  '  x := 1.0e16; WRITELN(x:18:1);' \
  '  x := 1000000000000000.0; WRITELN(x:18:1);' \
  '  x := 123456.789; WRITELN(x:12:3);' \
  '  x := 0.00001; WRITELN(x * 100000.0 = 1.0);' \
  '  x := 0.000001; WRITELN(x * 1000000.0 = 1.0);' \
  '  x := 1.5E3; WRITELN(x:8:1);' \
  '  x := 100.0; WRITELN(x:8:1);' \
  '  x := -0.0; WRITELN(1.0 / x < 0.0, 1.0 / NZERO < 0.0, 1.0 / NNEG > 0.0);' \
  '  WRITELN(NEG:6:2, NMAX < 0.0)' 'END.' > "$work/reals.pas"
for dialect in vintage extended; do
  bin/pascal1981 --dialect "$dialect" "$work/reals.pas" -o "$work/orig"
  "$work/orig" > "$work/expected"
  grep -qx TRUETRUETRUE "$work/expected" || die "$dialect -0.0 lost its sign"
  bin/lexer < "$work/reals.pas" | bin/parser --dialect "$dialect" > "$work/parsed.json"
  bin/typechecker --dialect "$dialect" < "$work/parsed.json" > "$work/typed.json"
  for stage in parsed typed; do
    bin/pretty81 < "$work/$stage.json" > "$work/pretty.pas" || die "$dialect $stage pretty81 failed"
    bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/reparsed.json"
    # The stages print a REAL with its shortest exact spelling, so equal
    # text is equal bits.
    for ast in "$stage" reparsed; do
      jq -c '[.. | objects | select(.__node_type__? == "RealLiteral") | .value]' \
        "$work/$ast.json" > "$work/$ast.values"
    done
    [[ $(jq length "$work/reparsed.values") -eq 38 ]] || die "$dialect $stage REAL literal count"
    diff -u "$work/$stage.values" "$work/reparsed.values" || die "$dialect $stage REAL values changed"
    bin/pretty81 < "$work/reparsed.json" > "$work/again.pas"
    diff -u "$work/pretty.pas" "$work/again.pas" || die "$dialect $stage not idempotent"
    pass "$dialect $stage exact/idempotent REAL round-trip"
    bin/pascal1981 --dialect "$dialect" "$work/pretty.pas" -o "$work/pretty"
    "$work/pretty" > "$work/actual"
    diff -u "$work/expected" "$work/actual" || die "$dialect $stage runtime values changed"
    pass "$dialect $stage runtime values"
  done
done
# The spellings: shortest exact digits, plain decimal for exponents -5..15,
# otherwise an E exponent (docs/ebnf_grammar.md real_literal).
for spelling in 'x := 0.1;' 'x := 0.30000000000000004;' \
  'x := 1.7976931348623157E308;' '1.7976931348623155E308' \
  'x := 2.2250738585072014E-308;' 'x := 5.0E-324;' \
  'x := 1.2345678901234568E22;' 'x := 1.0E20;' 'x := 1.0E16;' \
  'x := 1000000000000000.0;' 'x := 123456.789;' 'x := 0.00001;' \
  'x := 1.0E-6;' 'x := 1500.0;' 'x := 100.0;' \
  'NEG = -2.5;' 'NMAX = -1.7976931348623157E308;' 'NZERO = -0.0;' \
  'NNEG = -NZERO;'; do
  grep -qF -- "$spelling" "$work/pretty.pas" || die "spelling $spelling"
done
pass 'REAL literal spellings'
# A REAL literal past INTEGER range used to abort pretty81 in TRUNC.
golden=tests/corpus/golden/real_literal_wide_integer_part
bin/lexer < "$golden.pas" | bin/parser > "$work/wide.json"
bin/pretty81 < "$work/wide.json" > "$work/wide.pas" || die 'wide REAL literal aborted pretty81'
bin/pascal1981 "$work/wide.pas" -o "$work/wide"
"$work/wide" > "$work/wide.out"
diff -u "$golden.out" "$work/wide.out" || die 'wide REAL round-trip runtime values changed'
pass 'wide REAL literal round-trip'
# A null REAL value (no finite double) has no literal: fail, not garbage.
printf '%s\n' 'PROGRAM edge(OUTPUT); BEGIN WRITELN(1.5) END.' | bin/lexer | bin/parser > "$work/edge.json"
jq 'walk(if type == "object" and .__node_type__? == "RealLiteral" then .value = null else . end)' \
  "$work/edge.json" > "$work/null.json"
if bin/pretty81 < "$work/null.json" > "$work/null.pas" 2> "$work/null.err"; then
  die 'null REAL value was formatted'
fi
grep -qF 'REAL literal value is not a finite number' "$work/null.err" || die 'null REAL diagnostic'
pass 'non-finite REAL value rejected'
finish 'pretty81 reals'
