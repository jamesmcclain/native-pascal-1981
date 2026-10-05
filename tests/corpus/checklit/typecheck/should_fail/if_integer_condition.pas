{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: IF condition must be BOOLEAN }
PROGRAM P;
BEGIN
  IF 42 THEN WRITELN(1)
END.
