{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Array index must be an ordinal type }
PROGRAM P;
VAR a: ARRAY[1..10] OF INTEGER;
VAR r: REAL;
BEGIN
  r := 1.0;
  a[r] := 5
END.
