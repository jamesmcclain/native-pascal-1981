PROGRAM bad;
TYPE R = RECORD f: INTEGER END;
PROCEDURE probe;
VAR u, x, y: INTEGER; r: R;
BEGIN
  {$INITCK+}
  WRITELN('prefix');
  {$INITCK-}
  r.f := 1; WITH r DO BEGIN {$INITCK+} WRITELN(u) {$INITCK-} END;
  WRITELN('after')
END;
BEGIN probe END.
