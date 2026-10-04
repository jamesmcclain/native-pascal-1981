PROGRAM InitckDefiniteOk;
{$INITCK+}
PROCEDURE Straight;
VAR x, y: INTEGER;
BEGIN
  {$INITCK-} x := -32768; {$INITCK+}
  y := x + 1;
  x := y;
  WRITELN(x)
END;
PROCEDURE Joined(flag: BOOLEAN);
VAR x, y: INTEGER;
BEGIN
  IF flag THEN x := 0 ELSE x := 1;
  y := x;
  WRITELN(y)
END;
PROCEDURE Scalars;
VAR b, c: BOOLEAN; x, y: CHAR;
BEGIN
  b := FALSE; c := b;
  x := 'A'; y := x;
  IF c THEN WRITELN(1) ELSE WRITELN(y)
END;
BEGIN
  Straight;
  Joined(TRUE);
  Joined(FALSE);
  Scalars
END.
