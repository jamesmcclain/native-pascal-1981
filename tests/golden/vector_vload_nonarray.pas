{ DIALECT: extended }
PROGRAM VLoadNonArray(output);
{ VLOAD's first argument must be an array; a scalar pointee is rejected. }
TYPE
  PR = ^REAL32;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PR;
  v: V4F;
BEGIN
  NEW(p);
  v := VLOAD(p^, 0, V4F)
END.
