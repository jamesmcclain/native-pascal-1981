{ A named array index must be a type, not a value. A CONST identifier
  in index position is a typecheck error, not an implicit 0..V range. }
PROGRAM ArrayNamedIndexValueConstant(OUTPUT);
CONST
  V = 1;
VAR
  a: ARRAY [V] OF INTEGER;
BEGIN
END.
