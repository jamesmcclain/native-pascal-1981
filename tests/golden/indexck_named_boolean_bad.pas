PROGRAM indexck_named_boolean_bad(OUTPUT);
VAR
  a: ARRAY [BOOLEAN] OF INTEGER;
  i: INTEGER;
BEGIN
  i := 5;
  a[i] := 7
END.
