{ DIALECT: extended }
PROGRAM VStoreElemMismatch(output);
{ The array element type must match the vector element type exactly, also
  through a dereferenced SUPER ARRAY. }
TYPE
  FB = SUPER ARRAY [0..*] OF REAL;
  PFB = ^FB;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PFB;
BEGIN
  NEW(p, 15);
  VSTORE(p^, 0, VSPLAT(1.0, V4F))
END.
