{ A named array index must be ordinal. The typechecker rejects a REAL
  type name with the same diagnostic an explicit non-ordinal range gets. }
PROGRAM ArrayNamedIndexRealType(OUTPUT);
TYPE
  R = REAL;
VAR
  a: ARRAY [R] OF INTEGER;
BEGIN
END.
