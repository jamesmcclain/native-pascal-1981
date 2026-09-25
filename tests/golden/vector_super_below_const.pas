{ DIALECT: extended }
PROGRAM VectorSuperBelowConst(output);
{ The lower bound of a SUPER ARRAY is static, so a constant index below it
  is still a compile-time error even through p^. }
TYPE
  FB = SUPER ARRAY [1..*] OF REAL32;
  PFB = ^FB;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PFB;
BEGIN
  NEW(p, 21);
  VSTORE(p^, 0, VSPLAT(1.0, V4F))
END.
