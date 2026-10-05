{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Argument count mismatch }
PROGRAM P;
PROCEDURE Q(a, b: INTEGER);
BEGIN
END;
BEGIN
  Q(1)
END.
