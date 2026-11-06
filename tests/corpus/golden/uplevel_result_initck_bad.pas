{ DIALECT: vintage extended }
{ NEW-26: a nested routine's assignment to its enclosing FUNCTION's
  result initializes the result's INITCK state; a call that leaves it
  unset fails at the FUNCTION's END. }
{$INITCK+}
PROGRAM uplevel_result_initck_bad(OUTPUT);
FUNCTION Outer(n: INTEGER): INTEGER;
  PROCEDURE Inner(k: INTEGER);
  BEGIN
    IF k > 0 THEN Outer := k;
  END;
BEGIN
  Inner(n);
END;
PROCEDURE Main;
VAR r: INTEGER;
BEGIN
  r := Outer(5);
  WRITELN(r);
  r := Outer(0);
  WRITELN(r);
END;
BEGIN
  Main;
END.
