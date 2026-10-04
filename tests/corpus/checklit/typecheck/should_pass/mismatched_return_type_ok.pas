{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
FUNCTION F: INTEGER;
BEGIN
  F := 42
END;
BEGIN
  WRITELN(F)
END.
