PROGRAM onceir;
PROCEDURE probe(i: INTEGER);
VAR a: ARRAY [1..3] OF INTEGER; y: INTEGER;
BEGIN
  {$INDEXCK-} a[1] := 0;
  {$INITCK+} y := a[i] {$INITCK-}
END;
BEGIN probe(1) END.
