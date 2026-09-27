{ Named BOOLEAN and enum index types keep the existing index-expression
  contract: any ordinal expression is accepted, a non-ordinal (REAL) one is
  rejected exactly as for an explicit FALSE..TRUE range. }
PROGRAM ArrayNamedIndexNonOrdinalExpr(OUTPUT);
VAR
  a: ARRAY [BOOLEAN] OF INTEGER;
  r: REAL;
BEGIN
  r := 1.0;
  a[r] := 2
END.
