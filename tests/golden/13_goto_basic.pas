PROGRAM GotoBasic(OUTPUT);
LABEL 1, done, top;
VAR
  i: INTEGER;
BEGIN
  { Forward GOTO skips dead code. }
  GOTO 1;
  WRITELN('should not print');
1:
  WRITELN('forward goto ok');

  { Backward GOTO forms a loop. }
  i := 0;
top:
  i := i + 1;
  WRITELN(i);
  IF i < 3 THEN GOTO top;

  { GOTO escaping out of nested loops to code after them. }
  FOR i := 1 TO 5 DO
  BEGIN
    IF i = 2 THEN GOTO done;
    WRITELN('inner ', i);
  END;
  WRITELN('unreached');
done:
  WRITELN('escaped loop');
END.
