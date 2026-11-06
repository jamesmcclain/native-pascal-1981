{ DIALECT: vintage extended }
{ NEW-26: RANGECK guards a store from a nested routine into an enclosing
  routine's subrange local, read from its VAR formal. }
{$RANGECK+}
PROGRAM uplevel_rangeck_bad(OUTPUT);
PROCEDURE Outer(VAR s: INTEGER);
VAR r: 1..10;
  PROCEDURE Poke;
  BEGIN
    r := s;
  END;
BEGIN
  Poke;
  WRITELN(r);
END;
VAR n: INTEGER;
BEGIN
  n := 11;
  Outer(n);
END.
