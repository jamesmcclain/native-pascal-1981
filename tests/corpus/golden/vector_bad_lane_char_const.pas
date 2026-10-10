{ DIALECT: extended }
PROGRAM VectorBadLaneCharConst(output);
{ A lane count is an integer. A CHAR or BOOLEAN CONST has a known ordinal
  value, but it is not an integer CONST, so CHR(4) is not 4 lanes. }
CONST
  L = CHR(4);
TYPE
  V = VECTOR [L] OF REAL32;
VAR a: V;
BEGIN
  a := a
END.
