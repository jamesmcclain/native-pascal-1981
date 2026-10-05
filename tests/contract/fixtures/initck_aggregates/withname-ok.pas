PROGRAM withnameok;
TYPE P = RECORD x, y: INTEGER END;
PROCEDURE probe;
VAR x: REAL; r: P;
BEGIN
  x := 1.5; r.x := 4;
  {$INITCK+} WITH r DO WRITELN(x) {$INITCK-};
  WRITELN(x:3:1)
END;
BEGIN probe END.
