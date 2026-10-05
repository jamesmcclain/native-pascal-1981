PROGRAM benchaggregate;
TYPE Pair = RECORD a, b: INTEGER END;
{$INITCK+}
PROCEDURE update(VAR r: Pair);
BEGIN r.a := (r.a + 1) MOD 1000 END;
PROCEDURE probe;
VAR r, s: Pair; i, j: INTEGER;
BEGIN
  READLN(r.a); r.b := 7;
  FOR j := 1 TO 1000 DO
    FOR i := 1 TO 30000 DO
    BEGIN update(r); s := r; r := s END;
  WRITELN(s.a, ':', s.b)
END;
BEGIN probe END.
