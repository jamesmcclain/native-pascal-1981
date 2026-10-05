{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Undefined function: F }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  x := F(1)
END.
