{ DIALECT: vintage extended }
{ NEW-40: integer array index bounds must be checked by the typechecker, just
  like subrange bounds: a negative lower bound in a WORD range (-5..40000), a
  bound below -32768, and a reversed range are located typechecker errors. }
PROGRAM ArrayIndexBoundErrors;
VAR
  a: ARRAY [-5..40000] OF INTEGER;
  b: ARRAY [-40000..0] OF INTEGER;
  c: ARRAY [5..1] OF INTEGER;
BEGIN
END.
