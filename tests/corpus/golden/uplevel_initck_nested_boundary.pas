{ DIALECT: vintage extended }
{ NEW-26: an enclosing routine's local is captured storage, outside the
  INITCK slice: an enabled read of it in the nested routine is a compile
  error, never an unchecked pass. }
PROGRAM uplevel_initck_nested_boundary(OUTPUT);
PROCEDURE Outer(VAR q: INTEGER);
VAR x: INTEGER;
  PROCEDURE Inner;
  BEGIN
    {$INITCK+}
    WRITELN(x);
    {$INITCK-}
  END;
BEGIN
  x := 1;
  Inner;
END;
VAR z: INTEGER;
BEGIN
  z := 1;
  Outer(z);
END.
