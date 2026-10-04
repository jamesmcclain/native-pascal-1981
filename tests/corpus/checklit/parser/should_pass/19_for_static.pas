{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
PROGRAM P;
VAR i: INTEGER;
BEGIN
  FOR STATIC i := 1 TO 3 DO i := i + 1
END.
