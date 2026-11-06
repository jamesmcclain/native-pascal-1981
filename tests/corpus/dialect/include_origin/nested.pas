{ Nested includes: nested_outer.inc includes nested_inner.inc, then
  continues. An INDEXCK failure in the outer file's code after the inner
  include names the outer file at its own line, so returning from the
  inner file restored the outer file's name and position. }
PROGRAM nested(OUTPUT);
VAR a: ARRAY [1..5] OF INTEGER;
(*$INCLUDE:'nested_outer.inc'*)
BEGIN
  WRITELN(Twice(2));
  SetAt(9)
END.
