{ Nested includes: a MATHCK overflow in nested_inner.inc, which is reached
  only through nested_outer.inc, names the inner file. }
PROGRAM nested_inner_error(OUTPUT);
VAR a: ARRAY [1..5] OF INTEGER;
(*$INCLUDE:'nested_outer.inc'*)
BEGIN
  SetAt(2);
  WRITELN(a[2]);
  WRITELN(Twice(20000))
END.
