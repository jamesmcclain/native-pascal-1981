{ DIALECT: vintage }
{ NEW-40: vintage has no INTEGER32, so array index bounds above 65535 must be
  rejected by the typechecker rather than slipping through to codegen. }
PROGRAM VintageArrayBoundTooWide;
VAR
  ok: ARRAY [0..65535] OF CHAR;
  a: ARRAY [0..65536] OF CHAR;
  b: ARRAY [0..80000] OF CHAR;
BEGIN
END.
