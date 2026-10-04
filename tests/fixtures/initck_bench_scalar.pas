PROGRAM benchscalar;
{$INITCK+}
PROCEDURE probe;
VAR x, i, j: INTEGER;
BEGIN
  READLN(x);
  FOR j := 1 TO 2000 DO
    FOR i := 1 TO 30000 DO x := (x + 1) MOD 1000;
  WRITELN(x)
END;
BEGIN probe END.
