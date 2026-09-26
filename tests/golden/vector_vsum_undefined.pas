{ DIALECT: extended }
PROGRAM vector_vsum_undefined(OUTPUT);
{ VSUM of an undefined name is reported, not an INDEXCK abort inside the
  typechecker (its VECTOR probe indexed symbols[0] behind an eager AND). }
BEGIN
  WRITELN(VSUM(zz))
END.
