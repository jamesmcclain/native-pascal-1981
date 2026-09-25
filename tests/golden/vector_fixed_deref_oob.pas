{ DIALECT: extended }
PROGRAM VectorFixedDerefOob(output);
{ A fixed-bound array behind a pointer keeps compile-time rejection of a
  constant offset whose lanes run past the declared end. }
TYPE
  A8 = ARRAY [0..7] OF REAL32;
  PA = ^A8;
  V4F = VECTOR [4] OF REAL32;
VAR
  p: PA;
  w: V4F;
BEGIN
  NEW(p);
  w := VLOAD(p^, 5, V4F)
END.
