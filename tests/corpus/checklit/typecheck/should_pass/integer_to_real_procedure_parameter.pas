{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
PROCEDURE Q(x: REAL);
BEGIN
END;
BEGIN
  Q(1)
END.
