{ Every parser location (location, op_location, read_location) built from
  an included token carries its `file'; locations in the primary file,
  including the call after the include, carry none. }
{ CHECK-STAGES: lexer parser }
{ CHECK-COUNT: 5 tests/corpus/checklit/include_origin/inner.inc" }
{ CHECK-COUNT: 7 tests/corpus/checklit/include_origin/defs.inc" }
{ CHECK-COUNT: 12 "file": }
PROGRAM ast(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'tests/corpus/checklit/include_origin/defs.inc'*)
BEGIN
  Outer(1)
END.
