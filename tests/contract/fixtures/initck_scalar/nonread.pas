PROGRAM nonread;
VAR g: INTEGER; a: ARRAY [1..2] OF INTEGER;
PROCEDURE output(VAR v: INTEGER);
BEGIN v := 1 END;
PROCEDURE probe;
VAR x: INTEGER; p: ADRMEM;
BEGIN
  {$INITCK+} g := 1; p := ADR x; output(x); READ(x);
  WRITELN(SIZEOF(a), LOWER(a), UPPER(a))
  {$INITCK-}
END;
BEGIN probe END.
