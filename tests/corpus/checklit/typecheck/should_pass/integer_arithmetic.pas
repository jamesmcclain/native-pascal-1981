{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR x, y, z: INTEGER;
BEGIN
  x := 1; y := 2; z := x + y
END.
