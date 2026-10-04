PROGRAM ControlFlow(OUTPUT);
VAR
  i, sum: INTEGER;
BEGIN
  sum := 0;
  FOR i := 1 TO 5 DO
    sum := sum + i;
  WRITELN('for sum = ', sum);

  i := 3;
  WHILE i > 0 DO
  BEGIN
    WRITELN('countdown: ', i);
    i := i - 1;
  END;

  REPEAT
    i := i + 1;
  UNTIL i = 2;
  WRITELN('repeat final = ', i);
END.
