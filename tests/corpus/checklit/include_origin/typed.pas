{ The typechecker preserves the `file' of every location in the typed AST. }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-COUNT: 5 tests/corpus/checklit/include_origin/inner.inc" }
{ CHECK-COUNT: 7 tests/corpus/checklit/include_origin/defs.inc" }
{ CHECK-COUNT: 12 "file": }
PROGRAM typed(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'tests/corpus/checklit/include_origin/defs.inc'*)
BEGIN
  Outer(1)
END.
