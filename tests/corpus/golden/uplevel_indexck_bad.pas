{ DIALECT: vintage extended }
{ NEW-26: INDEXCK guards an enclosing routine's array indexed from a
  nested routine. }
{$INDEXCK+}
PROGRAM uplevel_indexck_bad(OUTPUT);
PROCEDURE Outer;
VAR v: ARRAY [1..3] OF INTEGER; i: INTEGER;
  PROCEDURE Poke;
  BEGIN
    v[i] := 1;
  END;
BEGIN
  i := 4;
  Poke;
END;
BEGIN
  Outer;
END.
