{ DIALECT: extended }
PROGRAM VectorSuperVarRejected(output);
{ A bare SUPER ARRAY variable has no runtime upper bound to check a
  VLOAD/VSTORE against, so it is rejected rather than lowered unchecked. }
TYPE
  FB = SUPER ARRAY [0..*] OF REAL32;
  V8F = VECTOR [8] OF REAL32;
VAR
  a: FB;
  v: V8F;
BEGIN
  v := VLOAD(a, 0, V8F)
END.
