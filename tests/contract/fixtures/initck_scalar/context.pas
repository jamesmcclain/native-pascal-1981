PROGRAM context;
PROCEDURE probe;
VAR unset: INTEGER;
BEGIN
  {$INITCK+}
  WRITELN((unset))
  {$INITCK-}
END;
BEGIN probe END.
