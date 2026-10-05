{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Cannot assign incompatible type without narrowing: b }
PROGRAM P;
VAR b: BOOLEAN;
BEGIN
  b := 1
END.
