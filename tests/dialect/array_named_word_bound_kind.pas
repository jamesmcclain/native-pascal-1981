{ LOWER/UPPER of ARRAY [WORD] are WORD-typed, like the explicit-range
  counterpart; assigning them to an INTEGER without narrowing is a
  typecheck error. }
PROGRAM ArrayNamedWordBoundKind(OUTPUT);
VAR
  f: ARRAY [WORD] OF INTEGER;
  i: INTEGER;
BEGIN
  i := LOWER(f)
END.
