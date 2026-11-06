#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Oversized numbers, metacommand values and source positions in the lexer.
#
# The lexer runs MATHCK- and RANGECK-checked, so an accumulator or counter
# that outgrows its type used to stop it with a run-time error inside the
# compiler (MTH-A-27). Each limit is now a located `Lexer Error:` or is
# handled exactly:
#   - a metacommand integer value outside INTEGER (-32768..32767);
#   - a metacommand name or value longer than its 255-character Str255;
#   - a radix literal with a base outside 2..36 or no digit after the `#'
#     (it used to lex as 0 followed by a second literal);
#   - a decimal or radix literal past 2^64 - 1, and a REAL literal past the
#     largest double (an exponent of any length is read by strtod);
#   - more than 32767 lines, or a line longer than 32767 characters: the
#     line and column counters are INTEGER32, and tokens keep exact positions;
#   - a numeric literal longer than 255 characters keeps its whole text as
#     the token lexeme, and no value depends on that text.
require bin/pascal1981 bin/lexer bin/parser bin/pretty81
command -v jq >/dev/null || die 'jq is required'

reject() { # label source expected-stderr
  printf '%s\n' "$2" > "$work/bad.pas"
  rm -f "$work/bad"
  if bin/pascal1981 "$work/bad.pas" -o "$work/bad" > "$work/stdout" 2> "$work/stderr"; then
    fail "$1" 'accepted'
    return
  fi
  if printf '%s\n' "$3" | diff -u - "$work/stderr" && [ ! -e "$work/bad" ]; then
    pass "$1"
  else
    fail "$1" 'diagnostic'
  fi
}

accept() { # label dialect source expected-stdout
  printf '%s\n' "$3" > "$work/ok.pas"
  rm -f "$work/ok"
  if bin/pascal1981 --dialect "$2" "$work/ok.pas" -o "$work/ok" 2> "$work/stderr" &&
     "$work/ok" > "$work/stdout" && printf '%s\n' "$4" | diff -u - "$work/stdout"; then
    pass "$1"
  else
    cat "$work/stderr"
    fail "$1"
  fi
}

# Metacommand integer values are INTEGER.
accept 'MATHCK:32767' vintage $'PROGRAM p;\n{$MATHCK:32767}\nBEGIN WRITELN(1) END.' 1
accept 'MATHCK:-32768' vintage $'PROGRAM p;\n{$MATHCK:-32768}\nBEGIN WRITELN(1) END.' 1
reject 'MATHCK:32768' $'PROGRAM p;\n{$MATHCK:32768}\nBEGIN END.' \
  'Lexer Error: metacommand integer value out of range at line 2 column 15'
reject 'MATHCK:-32769' $'PROGRAM p;\n{$MATHCK:-32769}\nBEGIN END.' \
  'Lexer Error: metacommand integer value out of range at line 2 column 16'
reject 'MATHCK:<30 digits>' $'PROGRAM p;\n{$MATHCK:123456789012345678901234567890}\nBEGIN END.' \
  'Lexer Error: metacommand integer value out of range at line 2 column 40'
long=$(printf '%*s' 300 '' | tr ' ' 7)
reject 'MATHCK:<300 digits>' $'PROGRAM p;\n{$MATHCK:'"$long"$'}\nBEGIN END.' \
  'Lexer Error: metacommand name or value exceeds 255 characters at line 2 column 265'
name=$(printf '%*s' 300 '' | tr ' ' A)
reject 'metacommand name of 300 characters' $'PROGRAM p;\n{$'"$name"$'}\nBEGIN END.' \
  'Lexer Error: metacommand name or value exceeds 255 characters at line 2 column 258'

# Radix literals.
accept 'radix 16#FF and 2#1010' vintage $'PROGRAM p;\nBEGIN WRITELN(16#FF, \' \', 2#1010) END.' '255 10'
for bad in '16#' '0#1' '1#0' '37#1' '99999999999999999999#1' '16#G'; do
  reject "radix $bad" $'PROGRAM p;\nVAR i: INTEGER;\nBEGIN i := '"$bad"$' END.' \
    'Lexer Error: bad radix constant at line 3 column 12'
done
reject 'radix literal past 2^64 - 1' $'PROGRAM p;\nVAR i: INTEGER;\nBEGIN i := 16#10000000000000000 END.' \
  'Lexer Error: integer literal exceeds 18446744073709551615 at line 3 column 12'

# Decimal and REAL literals of any length.
digits=$(printf '%*s' 400 '' | tr ' ' 9)
reject 'decimal literal of 400 digits' $'PROGRAM p;\nVAR i: INTEGER;\nBEGIN i := '"$digits"$' END.' \
  'Lexer Error: integer literal exceeds 18446744073709551615 at line 3 column 12'
reject 'REAL exponent of 400 digits' $'PROGRAM p;\nVAR r: REAL;\nBEGIN r := 1.0E'"$digits"$' END.' \
  'Lexer Error: REAL literal out of range at line 3 column 12'
accept 'REAL negative exponent of 400 digits' vintage \
  $'PROGRAM p;\nVAR r: REAL;\nBEGIN r := 1.0E-'"$digits"$'; WRITELN(r = 0.0) END.' TRUE

# Positions past 32767: many lines, and one long line. The error's
# position is exact, so the counters did not wrap.
{
  printf 'PROGRAM big;\nVAR i: INTEGER;\nBEGIN\n'
  for ((k = 0; k < 33000; k++)); do printf '  i := 1;\n'; done
  printf '  WRITELN(i)\nEND.\n'
} > "$work/lines.pas"
bin/pascal1981 "$work/lines.pas" -o "$work/lines" && "$work/lines" > "$work/stdout" &&
  printf '1\n' | diff -u - "$work/stdout" && pass '33000-line program' || fail '33000-line program'
{
  printf 'PROGRAM wide;\nVAR i: INTEGER;\nBEGIN'
  for ((k = 0; k < 4000; k++)); do printf ' i := 1; '; done
  printf '\n  WRITELN(i)\nEND.\n'
} > "$work/wide.pas"
bin/pascal1981 "$work/wide.pas" -o "$work/wide" && "$work/wide" > "$work/stdout" &&
  printf '1\n' | diff -u - "$work/stdout" && pass '36000-column line' || fail '36000-column line'
{
  printf 'PROGRAM far;\nBEGIN\n'
  for ((k = 0; k < 40000; k++)); do printf '\n'; done
  printf '  i := 16#\nEND.\n'
} > "$work/far.pas"
if bin/pascal1981 "$work/far.pas" -o "$work/far" > /dev/null 2> "$work/stderr"; then
  fail 'error at line 40003' 'accepted'
else
  printf 'Lexer Error: bad radix constant at line 40003 column 8\n' | diff -u - "$work/stderr" &&
    pass 'error at line 40003' || fail 'error at line 40003'
fi
# A numeric literal longer than 255 characters (NEW-11). Its value is read
# from the whole text, and the token's lexeme now carries the whole text
# too; a Str255 copy used to stop at 255 characters. No stage takes a value
# from that text: the first 255 characters of each literal here spell 0,
# and numeric labels, which the parser used to key on the lexeme, all
# collided at 0. pretty81 used to print every numeric label (and the label
# of BREAK/CYCLE) as nothing.
zeros=$(printf '%*s' 300 '' | tr ' ' 0)
real="0.${zeros}1E302"
int="${zeros}42"
cat > "$work/long.pas" <<EOF
PROGRAM long(OUTPUT);
LABEL ${zeros}7, ${zeros}8, outer;
CONST R = ${real}; N = ${int};
VAR x: REAL; i, j: INTEGER;
BEGIN
  outer: FOR i := 1 TO 3 DO
    FOR j := 1 TO 3 DO
    BEGIN
      IF j = 2 THEN CYCLE outer;
      IF i = 3 THEN BREAK outer;
      WRITELN(i, j)
    END;
  x := ${real};
  WRITELN(x:5:1, R:5:1, ${int}, N, ${int} + 0 = 42);
  GOTO ${zeros}8;
  ${zeros}7: WRITELN('seven');
  ${zeros}8: WRITELN('eight')
END.
EOF
printf '%s\n' 11 21 ' 10.0 10.04242TRUE' eight > "$work/long.expected"
bin/lexer < "$work/long.pas" > "$work/long.tokens"
jq -r '.[] | select(.kind == "REAL_LITERAL" or .kind == "INTEGER_LITERAL")
         | .lexeme | select(length > 255)' \
  "$work/long.tokens" | sort -u > "$work/long.lexemes"
printf '%s\n' "${zeros}42" "${zeros}7" "${zeros}8" "$real" | sort -u |
  diff -u - "$work/long.lexemes" && pass 'long literal lexemes keep their whole text' ||
  fail 'long literal lexemes keep their whole text'
for dialect in vintage extended; do
  for opt in 0 2; do
    if bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/long.pas" -o "$work/long" &&
       "$work/long" > "$work/stdout" && diff -u "$work/long.expected" "$work/stdout"; then
      pass "long literals and labels $dialect O$opt"
    else
      fail "long literals and labels $dialect O$opt"
    fi
  done
  # pretty81 prints each value and label key from the AST, not from the
  # source text.
  bin/lexer < "$work/long.pas" | bin/parser --dialect "$dialect" > "$work/long.json"
  if bin/pretty81 < "$work/long.json" > "$work/long_pretty.pas" &&
     bin/pascal1981 --dialect "$dialect" "$work/long_pretty.pas" -o "$work/long_pretty" &&
     "$work/long_pretty" > "$work/stdout" && diff -u "$work/long.expected" "$work/stdout"; then
    pass "long literals through pretty81 $dialect"
  else
    fail "long literals through pretty81 $dialect"
  fi
done
finish 'lexer numeric limits'
