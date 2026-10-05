{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Argument type mismatch or implicit narrowing in call to Q }
PROGRAM P;
PROCEDURE Q(x: INTEGER);
BEGIN
END;
BEGIN
  Q(3.14)
END.
