{ A named array index must be a declared type. The typechecker rejects
  an undeclared identifier in type position before codegen runs. }
PROGRAM ArrayNamedIndexMissing(OUTPUT);
VAR
  a: ARRAY [missing] OF INTEGER;
BEGIN
END.
