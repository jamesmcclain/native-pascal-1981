{ Included tokens carry the include path as written as their `file'; the
  primary file's tokens carry none. defs.inc has 16 tokens and includes
  inner.inc (9 tokens) before its own; check mode runs from the repository
  root, where include paths resolve. }
{ CHECK-STAGES: lexer }
{ CHECK-COUNT: 9 tests/corpus/checklit/include_origin/inner.inc" }
{ CHECK-COUNT: 16 tests/corpus/checklit/include_origin/defs.inc" }
{ CHECK-COUNT: 25 "file": }
PROGRAM tokens(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'tests/corpus/checklit/include_origin/defs.inc'*)
BEGIN
  Outer(1)
END.
