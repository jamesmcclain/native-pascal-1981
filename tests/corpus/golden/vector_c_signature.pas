{ DIALECT: extended }
PROGRAM VectorCSignature(output);
{ A VECTOR has no stable C ABI here, so it may not appear in a [C]
  routine's parameters or return type. }
TYPE V4 = VECTOR [4] OF INTEGER32;
PROCEDURE Sink(v: V4) [C]; EXTERN;
VAR a: V4;
BEGIN
  a := a;
  Sink(a)
END.
