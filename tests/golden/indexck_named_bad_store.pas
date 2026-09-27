PROGRAM indexck_named_bad_store(OUTPUT);
TYPE
  Index = 2..4;
VAR
  a: ARRAY [Index] OF INTEGER;
  i: INTEGER;
BEGIN
  i := 9;
  a[i] := 7
END.
