PROGRAM copyok;
PROCEDURE probe;
VAR x, y, z: INTEGER; b: BOOLEAN; c, d: CHAR;
BEGIN
  {$INITCK-}
  x := 0; y := x; z := y - 32767 - 1;
  b := y = z;
  c := 'q'; d := c;
  {$INITCK+} WRITELN(y, ' ', z, ' ', ORD(b), d)
  {$INITCK-}
END;
PROCEDURE retaint;
VAR unset, y: INTEGER;
BEGIN
  { Overwriting a slot that received unset state initializes it again. }
  {$INITCK-} y := unset; y := 7;
  {$INITCK+} WRITELN(y)
  {$INITCK-}
END;
BEGIN probe; retaint END.
