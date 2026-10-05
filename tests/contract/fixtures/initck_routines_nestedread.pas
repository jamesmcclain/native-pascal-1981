PROGRAM bad;
PROCEDURE probe;
VAR u, x, y: INTEGER;
PROCEDURE inner; VAR x: INTEGER; BEGIN {$INITCK+} WRITELN(x) {$INITCK-} END;
BEGIN
  {$INITCK+}
  WRITELN('prefix');
  {$INITCK-}
  x := 1; inner;
  WRITELN('after')
END;
BEGIN probe END.
