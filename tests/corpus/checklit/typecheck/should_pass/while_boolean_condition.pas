{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  x := 0;
  WHILE x < 10 DO x := x + 1
END.
