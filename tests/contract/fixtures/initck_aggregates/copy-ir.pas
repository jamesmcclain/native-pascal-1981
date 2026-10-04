PROGRAM copyir;
TYPE P = RECORD x, y: INTEGER END;
PROCEDURE probe;
VAR a, b, c: P;
BEGIN
  a.x := 1; a.y := 2;
  {$INITCK+} b := a; {$INITCK-} c := a
END;
BEGIN probe END.
