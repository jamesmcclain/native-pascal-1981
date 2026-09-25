{ DIALECT: extended }
PROGRAM VectorSuperVLoadBelow(output);
{ A variable-index VLOAD starting below LOWER(p^) is a run-time error. }
TYPE
  FB = SUPER ARRAY [1..*] OF REAL32;
  PFB = ^FB;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PFB;
  v: V4F;
  i: INTEGER;
BEGIN
  NEW(p, 21);
  i := 0;
  v := VLOAD(p^, i, V4F);
  WRITELN('not reached')
END.
