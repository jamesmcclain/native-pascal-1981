{ DIALECT: extended }
PROGRAM VectorSuperVLoadOobVar(output);
{ A variable-index VLOAD whose last lane is one past UPPER(p^) is a
  run-time error: the whole lane range is checked before the load. }
TYPE
  FB = SUPER ARRAY [1..*] OF REAL32;
  PFB = ^FB;
  V8F = VECTOR [8] OF REAL32;
VAR
  p: PFB;
  v: V8F;
  i: INTEGER32;
BEGIN
  NEW(p, 21);
  i := 14;
  v := VLOAD(p^, i, V8F);
  WRITELN('in range');
  i := 15;
  v := VLOAD(p^, i, V8F);
  WRITELN('not reached')
END.
