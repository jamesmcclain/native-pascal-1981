{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  WRITELN(x)
END.
