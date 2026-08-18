PROGRAM LabeledBreakCycle(OUTPUT);
VAR
  i, j: INTEGER;
BEGIN
  { Labeled BREAK from an inner loop targets the outer loop. }
  outer: FOR i := 1 TO 3 DO
  BEGIN
    FOR j := 1 TO 3 DO
    BEGIN
      IF j = 2 THEN BREAK outer;
      WRITELN('outer=', i, ' inner=', j);
    END;
  END;
  WRITELN('after outer break');

  { Labeled CYCLE from an inner loop continues the outer loop. }
  again: FOR i := 1 TO 3 DO
  BEGIN
    FOR j := 1 TO 3 DO
    BEGIN
      IF j = 2 THEN CYCLE again;
      WRITELN('again outer=', i, ' inner=', j);
    END;
  END;
  WRITELN('after outer cycle');
END.
