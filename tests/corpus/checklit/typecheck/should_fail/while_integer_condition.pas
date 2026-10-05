{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: WHILE condition must be BOOLEAN }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  WHILE x DO x := x + 1
END.
