{$INITCK+}
PROGRAM boundarygate;
VAR g: INTEGER; r: REAL;
PROCEDURE probe;
BEGIN
  {$PUSH,INITCK-,DEBUG+,INITCK+}
  g := 1; r := 1.0;
  {$POP}
  WRITELN(g);
  {$INITCK-,INITCK+}
  WRITELN(r:3:1)
END;
BEGIN probe END.
