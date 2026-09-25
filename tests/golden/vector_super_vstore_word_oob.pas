{ DIALECT: extended }
PROGRAM VectorSuperVStoreWordOob(output);
{ A WORD index is unsigned: 65535 is far past the end, not -1. }
TYPE
  FB = SUPER ARRAY [0..*] OF REAL32;
  PFB = ^FB;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PFB;
  k: WORD;
BEGIN
  NEW(p, 15);
  k := 65535;
  VSTORE(p^, k, VSPLAT(1.0, V4F));
  WRITELN('not reached')
END.
