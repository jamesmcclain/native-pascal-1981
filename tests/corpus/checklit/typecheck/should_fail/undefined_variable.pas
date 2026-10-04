{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Undefined identifier: x }
PROGRAM P;
BEGIN
  WRITELN(x)
END.
