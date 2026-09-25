{ DIALECT: extended }
PROGRAM VectorSuperVStoreOobConst(output);
{ A constant-index VSTORE past UPPER(p^) cannot be rejected at compile time
  (the bound is a run-time value), so it is a run-time error, raised once
  before any lane is written. }
TYPE
  FB = SUPER ARRAY [0..*] OF REAL32;
  PFB = ^FB;
  V8F = VECTOR [8] OF REAL32;
VAR
  p: PFB;
BEGIN
  NEW(p, 31);
  VSTORE(p^, 24, VSPLAT(1.0, V8F));
  WRITELN('in range');
  VSTORE(p^, 25, VSPLAT(1.0, V8F));
  WRITELN('not reached')
END.
