#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 prints AND THEN/OR ELSE chains without parentheses, which the 1981
# manual forbids around them: its output parses again, prints the same text,
# and the program behaves the same.
require bin/pretty81 bin/lexer bin/parser bin/pascal1981
cat > "$work/seq.pas" <<'P'
PROGRAM seq;
VAR i, n: INTEGER; v: ARRAY [1..3] OF INTEGER;
BEGIN
  v[1] := 4; v[2] := 5; v[3] := 6; n := 0;
  i := 1;
  WHILE i <= 3 AND THEN v[i] <> 6 DO i := i + 1;
  WRITELN(i);
  IF (i > 3) AND THEN (v[i] = 0) OR ELSE (i = 3) AND THEN NOT (v[i] = 5) THEN WRITELN('chain');
  REPEAT n := n + 1 UNTIL n = 0 OR ELSE (12 DIV n) = 4;
  WRITELN(n)
END.
P
printf '3\nchain\n3\n' > "$work/expected"
for dialect in vintage extended; do
  bin/lexer < "$work/seq.pas" | bin/parser --dialect "$dialect" > "$work/parsed.json"
  bin/pretty81 < "$work/parsed.json" > "$work/pretty.pas"
  grep -q 'v\[i\] <> 6) DO' "$work/pretty.pas" || die "$dialect: WHILE chain printed with parentheses"
  bin/lexer < "$work/pretty.pas" | bin/parser --dialect "$dialect" > "$work/reparsed.json"
  bin/pretty81 < "$work/reparsed.json" | diff -u "$work/pretty.pas" -
  for src in seq pretty; do
    bin/pascal1981 --dialect "$dialect" "$work/$src.pas" -o "$work/$src"
    "$work/$src" | diff -u "$work/expected" -
  done
done
pass 'pretty81 prints AND THEN/OR ELSE chains that parse again and behave the same'
