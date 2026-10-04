PROGRAM readok;
PROCEDURE probe;
VAR n: INTEGER; c: CHAR; b: BOOLEAN;
BEGIN
  {$INITCK+}
  READ(n); READ(c); READLN(b);
  WRITELN(n + 1, c, ORD(b));
  READLN(n, c);
  WRITELN(n, c)
  {$INITCK-}
END;
BEGIN probe END.
