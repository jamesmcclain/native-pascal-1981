{ DIALECT: extended }
PROGRAM VectorSuperVLoadNil(output);
{ VLOAD through a NIL SUPER ARRAY pointer is a run-time error, detected
  before the bound header in front of the data is read. }
TYPE
  FB = SUPER ARRAY [0..*] OF REAL32;
  PFB = ^FB;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PFB;
  v: V4F;
BEGIN
  p := NIL;
  v := VLOAD(p^, 0, V4F);
  WRITELN('not reached')
END.
