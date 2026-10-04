PROGRAM validationfail;
PROCEDURE ignore(arg: INTEGER);
BEGIN END;
PROCEDURE probe;
VAR unset: INTEGER;
BEGIN
  WRITELN('prefix');
  {$INITCK+} ignore(unset);
  WRITELN('after')
  {$INITCK-}
END;
BEGIN probe END.
