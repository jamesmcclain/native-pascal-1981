{ DIALECT: extended }
{ A built-in ordinal whose full domain exceeds what a fixed array can
  hold is rejected. INTEGER32 passes the typechecker (the type is ordinal
  and its bounds are knowable) and is lowered by codegen, which rejects
  the domain size with its own stage-appropriate diagnostic. }
PROGRAM ArrayNamedIndexTooLarge(OUTPUT);
VAR
  a: ARRAY [INTEGER32] OF INTEGER;
BEGIN
END.
