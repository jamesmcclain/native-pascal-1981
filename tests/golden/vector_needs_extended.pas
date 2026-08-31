PROGRAM VectorNeedsExtended(output);
{ VECTOR is an extended-dialect construct. With no DIALECT line this fixture
  compiles as vintage, and the type declaration must be rejected. }
TYPE
  V4I = VECTOR [4] OF INTEGER;
VAR
  a: V4I;
BEGIN
  a := a
END.
