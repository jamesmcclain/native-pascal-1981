PROGRAM benchheap;
TYPE Row = ARRAY [1..64] OF INTEGER;
     Rows = SUPER ARRAY [1..*] OF Row;
{$INITCK+}
PROCEDURE probe;
VAR p: ^Rows; i, j, k, x: INTEGER;
BEGIN
  NEW(p, 30000);
  x := 0;
  FOR k := 1 TO 20 DO
  BEGIN
    FOR i := 1 TO 30000 DO
      FOR j := 1 TO 64 DO p^[i][j] := 1;
    FOR i := 1 TO 30000 DO
      FOR j := 1 TO 64 DO x := p^[i][j]
  END;
  WRITELN(x);
  DISPOSE(p)
END;
BEGIN probe END.
