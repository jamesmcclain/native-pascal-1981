{ DIALECT: extended }
PROGRAM ExtendedUnrollZero(output);
VAR
  i: INTEGER;
BEGIN
  {$UNROLL 0}
  FOR i := 1 TO 2 DO
    WRITELN(i)
END.
