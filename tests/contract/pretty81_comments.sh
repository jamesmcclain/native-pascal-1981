#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# pretty81 output is a fixed point: printing it again gives the same text,
# comments included (NEW-18).
#
# Every pass used to add a blank inside each comment's delimiters (the
# lexer keeps the blanks between them, and pretty81 wrapped that text in
# `{ ' and ` }' again), a trailing comment moved on to the next item of its
# list on every parse, and a comment ahead of an assignment, call or RETURN
# rode on a node in a later statement. A comment-heavy program ({ } and
# (* *) comments, multi-line ones with blank lines and tabs, leading,
# trailing, stacked, before PROGRAM) and a sample of the compiler's own
# sources are each printed twice and must print identically; the printed
# program must also still compile and behave the same.
require bin/pretty81 bin/lexer bin/parser bin/pascal1981

cat > "$work/comments.pas" <<'P'
{ Leading comment of the program. }
(* A parenthesised leading comment. *)
PROGRAM comments(OUTPUT);
{ Comment before CONST }
CONST
  K = 3; { trailing after K }
  L = 4; (* trailing star after L *)
{
  A multi-line comment

  with a blank line,	a tab	inside
  and indentation.
}
VAR
  i: INTEGER; {no spaces}
  j: INTEGER; {   lots of spaces   }
{one}{two}
{ first stacked }
{ second stacked }
PROCEDURE p; { after heading }
BEGIN { after BEGIN }
  { leading statement comment }
  WRITELN('p') { trailing statement comment }
END; { after END }
FUNCTION f(x: INTEGER): INTEGER;
BEGIN
  { before an assignment }
  f := x * 2 (* trailing star with a } brace *) (* and another *)
END;
BEGIN
  i := K; j := L;
	{	tab-indented comment	}
  IF i < j THEN { then-comment }
    p
  ELSE
    { else-comment }
    WRITELN('no');
  WHILE i > 0 DO
  BEGIN
    i := i - 1; {x}
  END;
  CASE i OF
    { before an arm }
    0: WRITELN('zero'); { case arm }
    1: WRITELN('one')
  END;
  WRITELN(f(2)) {}
END.
P
printf '%s\n' p zero 4 > "$work/expected"

twice() { # file dialect: print it twice through pretty81, require a fixed point
  local name=$1 dialect=$2 dir
  dir=$(dirname "$1")
  (cd "$dir" && "$ROOT/bin/lexer" < "$name") | bin/parser --dialect "$dialect" > "$work/p0.json" &&
    bin/pretty81 < "$work/p0.json" > "$work/p1.pas" &&
    bin/lexer < "$work/p1.pas" | bin/parser --dialect "$dialect" > "$work/p1.json" &&
    bin/pretty81 < "$work/p1.json" > "$work/p2.pas" &&
    diff -u "$work/p1.pas" "$work/p2.pas"
}

for dialect in vintage extended; do
  if twice "$work/comments.pas" "$dialect"; then
    pass "comment fixture prints identically twice ($dialect)"
  else
    fail "comment fixture prints identically twice ($dialect)"
  fi
  # The comments are kept, trimmed, each where the next pass reads it back.
  missing=0
  for line in '{ Leading comment of the program. }' '{ A parenthesised leading comment. }' \
      '  K = 3; { trailing after K }' '  L = 4; { trailing star after L }' \
      '  i: INTEGER; { no spaces }' '  j: INTEGER; { lots of spaces }' \
      '{ one }' '{ two }' '  { leading statement comment }' \
      "  WRITELN('p') { trailing statement comment };" '  { before an assignment }' \
      '  f := (x * 2) (* trailing star with a } brace *);' \
      '  { tab-indented comment }' '    { before an arm }' \
      "      WRITELN('zero') { case arm };" '  WRITELN(f(2)) { };'; do
    grep -qxF -- "$line" "$work/p1.pas" || { echo "missing: $line"; missing=1; }
  done
  grep -qxF -- $'  { A multi-line comment    with a blank line,\ta tab\tinside   and indentation. }' \
    "$work/p1.pas" || { echo 'missing: multi-line comment'; missing=1; }
  [[ $missing == 0 ]] && pass "comments kept in place ($dialect)" || fail "comments kept in place ($dialect)"
  if bin/pascal1981 --dialect "$dialect" "$work/p1.pas" -o "$work/p1" &&
     "$work/p1" > "$work/stdout" && diff -u "$work/expected" "$work/stdout"; then
    pass "printed comment fixture behaves the same ($dialect)"
  else
    fail "printed comment fixture behaves the same ($dialect)"
  fi
done

# Real sources: long header comments, comments inside routines, INTERFACE
# units spliced in from $INCLUDEd files.
for src in argparse lexer ps_base ps_stmt pretty81 tc_types cg_util; do
  if twice "$ROOT/src/$src.pas" extended; then
    pass "src/$src.pas prints identically twice"
  else
    fail "src/$src.pas prints identically twice"
  fi
done
finish 'pretty81 comments'
