PROGRAM validationok;
PROCEDURE probe;
VAR x: INTEGER;
BEGIN
  {$INITCK-} x := 0;
  {$INITCK+} WRITELN(x);
  x := -32768;
  WRITELN(x)
  {$INITCK-}
END;
BEGIN probe END.
