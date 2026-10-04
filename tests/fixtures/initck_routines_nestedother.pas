PROGRAM bad;
PROCEDURE probe;
VAR u, x, y: INTEGER;
PROCEDURE inner(x: INTEGER); VAR y: INTEGER; BEGIN y := x END;
BEGIN
  {$INITCK+}
  WRITELN('prefix');
  {$INITCK-}
  inner(1); {$INITCK+} WRITELN(x);
  WRITELN('after')
END;
BEGIN probe END.
