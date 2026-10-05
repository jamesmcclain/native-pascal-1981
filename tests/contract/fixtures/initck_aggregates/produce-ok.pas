PROGRAM produceok;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; r: RECORD c: CHAR; b: BOOLEAN END;
    t: ARRAY [1..2] OF INTEGER; i, y: INTEGER;
BEGIN
  {$INITCK-} a[1] := 4; r.b := TRUE; t[1] := a[1]; y := t[1] + a[1];
  i := 2; READLN(a[i]); READ(r.c);
  {$INITCK+} WRITELN(a[1], ' ', a[2], ' ', r.c, ORD(r.b), ' ', t[1], ' ', y)
  {$INITCK-}
END;
BEGIN probe END.
