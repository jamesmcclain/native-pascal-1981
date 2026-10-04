{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Cannot assign incompatible type without narrowing: F }
PROGRAM P;
FUNCTION F: INTEGER;
BEGIN
  F := 3.14
END;
BEGIN
END.
