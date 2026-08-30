PROGRAM VintageUnroll(output);
VAR
  i: INTEGER;
BEGIN
  {$UNROLL 4}
  FOR i := 1 TO 2 DO
    WRITELN(i)
END.
