{ DIALECT: extended }
{ A 64-bit integer domain is ordinal but its bounds are not representable,
  so it is rejected by the typechecker (as for WORD64) rather than passed
  to codegen's size check. }
PROGRAM ArrayNamedIndexInt64(OUTPUT);
VAR
  a: ARRAY [INTEGER64] OF INTEGER;
BEGIN
END.
