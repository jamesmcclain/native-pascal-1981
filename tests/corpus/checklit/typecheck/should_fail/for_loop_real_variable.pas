{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: FOR loop variable must be an ordinal type }
PROGRAM P;
VAR r: REAL;
BEGIN
  FOR r := 1.0 TO 10.0 DO WRITELN(r)
END.
