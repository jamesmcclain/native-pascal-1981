{ DIALECT: extended }
PROGRAM VectorPacked(output);
{ PACKED has no meaning for a VECTOR and is rejected at parse time. }
TYPE V = PACKED VECTOR [4] OF INTEGER32;
VAR a: V;
BEGIN
  a := a
END.
