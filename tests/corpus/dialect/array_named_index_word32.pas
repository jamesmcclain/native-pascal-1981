{ DIALECT: extended }
{ A 32-bit word domain is ordinal with knowable bounds, so it passes the
  typechecker and is rejected by codegen with its stage-appropriate size
  diagnostic. }
PROGRAM ArrayNamedIndexWord32(OUTPUT);
VAR
  a: ARRAY [WORD32] OF INTEGER;
BEGIN
END.
