{ DIALECT: extended }
PROGRAM VSplatBadType(output);
{ VSPLAT's second argument must name a VECTOR type, not a scalar type. }
TYPE
  V4D = VECTOR [4] OF REAL;
VAR
  v: V4D;
BEGIN
  v := VSPLAT(1.0, REAL)
END.
