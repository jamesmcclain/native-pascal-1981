{ DIALECT: vintage extended }
{ NEW-26: NILCK guards a dereference, in a nested routine, of an
  enclosing routine's pointer. }
{$NILCK+}
PROGRAM uplevel_nilck_bad(OUTPUT);
TYPE PI = ^INTEGER;
PROCEDURE Outer;
VAR p: PI;
  PROCEDURE Poke;
  BEGIN
    p^ := 1;
  END;
BEGIN
  p := NIL;
  Poke;
END;
BEGIN
  Outer;
END.
