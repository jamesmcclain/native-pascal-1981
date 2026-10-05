{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR b: BOOLEAN;
VAR x: INTEGER;
BEGIN
  IF b THEN x := 1
END.
