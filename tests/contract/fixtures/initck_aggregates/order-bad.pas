PROGRAM orderbad;
PROCEDURE probe;
VAR a: ARRAY [1..3] OF INTEGER; i: INTEGER;
BEGIN
  i := 4; WRITELN('prefix');
  {$INITCK+} WRITELN(a[i]) {$INITCK-}
END;
BEGIN probe END.
