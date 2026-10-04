{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR i: INTEGER;
BEGIN
  FOR i := 1 TO 10 DO WRITELN(i)
END.
