{ DIALECT: extended }
{ A 64-bit word domain is ordinal but its bounds are not representable, so
  it is rejected by the typechecker before codegen. }
PROGRAM ArrayNamedIndexWord64(OUTPUT);
VAR
  a: ARRAY [WORD64] OF INTEGER;
BEGIN
END.
