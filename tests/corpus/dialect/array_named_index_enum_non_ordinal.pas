{ A named enum index type keeps the same index-expression contract: a
  non-ordinal REAL expression is rejected, as for an explicit red..blue
  range. }
PROGRAM ArrayNamedIndexEnumNonOrdinal(OUTPUT);
TYPE
  Color = (red, green, blue);
VAR
  a: ARRAY [Color] OF INTEGER;
  r: REAL;
BEGIN
  r := 1.0;
  a[r] := 2
END.
