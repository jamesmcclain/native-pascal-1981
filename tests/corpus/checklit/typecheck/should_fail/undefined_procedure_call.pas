{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Undefined procedure: Q }
PROGRAM P;
BEGIN
  Q(1, 2)
END.
