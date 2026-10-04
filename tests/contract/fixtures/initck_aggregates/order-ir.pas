PROGRAM orderir;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; i, y: INTEGER;
BEGIN
  a[2] := 0; i := 2;
  {$INITCK+} y := a[i] {$INITCK-}
END;
BEGIN probe END.
