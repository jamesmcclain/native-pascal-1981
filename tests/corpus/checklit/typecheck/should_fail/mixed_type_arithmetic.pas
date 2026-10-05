{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Arithmetic operator requires numeric operands }
PROGRAM P;
VAR x: INTEGER;
VAR s: LSTRING(10);
BEGIN
  x := x + s
END.
