{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Cannot assign incompatible type without narrowing: x }
PROGRAM P;
VAR x: INTEGER;
BEGIN
  x := 3.14
END.
