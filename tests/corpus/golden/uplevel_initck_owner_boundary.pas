{ DIALECT: vintage extended }
{ NEW-26: a local that a nested routine names is disqualified from
  INITCK tracking in its own routine too: an enabled read there is the
  escaped local boundary. }
{$INITCK+}
PROGRAM uplevel_initck_owner_boundary(OUTPUT);
PROCEDURE Outer;
VAR x, y: INTEGER;
  PROCEDURE Inner;
  BEGIN
    x := 7;
  END;
BEGIN
  Inner;
  y := 2;
  WRITELN(y);
  WRITELN(x);
END;
BEGIN
  Outer;
END.
