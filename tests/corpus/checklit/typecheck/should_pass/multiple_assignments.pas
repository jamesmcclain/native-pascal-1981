{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  x := 1; x := 2; x := 3
END.
