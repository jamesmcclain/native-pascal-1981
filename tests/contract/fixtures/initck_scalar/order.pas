PROGRAM ordering;
PROCEDURE probe;
VAR x: INTEGER; b: BOOLEAN; c: CHAR;
BEGIN
  {$INITCK-} x := 0; b := FALSE; c := 'z';
  {$INITCK+} WRITELN(x, b, c);
  {$INITCK-} WRITELN(x)
END;
BEGIN probe END.
