{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
BEGIN
  IF TRUE THEN WRITELN(1)
END.
