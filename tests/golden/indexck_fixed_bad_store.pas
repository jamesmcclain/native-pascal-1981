PROGRAM indexck_fixed_bad_store(OUTPUT);
VAR a: ARRAY[2..3] OF INTEGER; i: INTEGER;
BEGIN
  i := 4;
  a[i] := 7
END.
