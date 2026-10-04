{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Undefined identifier: x }
PROGRAM P;
PROCEDURE P1;
VAR x: INTEGER;
BEGIN
END;
BEGIN
  WRITELN(x)
END.
