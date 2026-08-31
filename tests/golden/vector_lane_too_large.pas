{ DIALECT: extended }
PROGRAM VectorLaneTooLarge(output);
{ 128 is a power of two but above the 64-lane ceiling. }
TYPE V128 = VECTOR [128] OF INTEGER32;
VAR a: V128;
BEGIN
  a := a
END.
