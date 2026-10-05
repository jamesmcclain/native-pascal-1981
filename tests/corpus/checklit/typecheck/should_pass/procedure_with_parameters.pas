{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
PROCEDURE Q(a: INTEGER; b: INTEGER);
BEGIN
END;
BEGIN
  Q(1, 2)
END.
