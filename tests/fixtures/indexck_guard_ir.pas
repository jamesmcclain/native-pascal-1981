PROGRAM indexck_guard_ir(OUTPUT);
VAR a: ARRAY[1..2] OF INTEGER; i: INTEGER;
BEGIN
  i := 1;
  a[i] := 7;
  {$INDEXCK-} a[3] := 9;
END.
