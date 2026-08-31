{ DIALECT: extended }
PROGRAM VectorLaneNotPow2(output);
{ Lane count must be a power of two in 2..64. 6 is in range but not a
  power of two. }
TYPE V6 = VECTOR [6] OF INTEGER32;
VAR a: V6;
BEGIN
  a := a
END.
