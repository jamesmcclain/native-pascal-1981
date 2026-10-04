PROGRAM transport;
{$INITCK+}
FUNCTION pick(i: INTEGER; b: BOOLEAN; c: CHAR): INTEGER;
BEGIN IF b THEN pick := i ELSE pick := ORD(c) END;
FUNCTION same(b: BOOLEAN): BOOLEAN; BEGIN same := b END;
FUNCTION letter(c: CHAR): CHAR; BEGIN letter := c END;
PROCEDURE ignore(n: INTEGER); BEGIN END;
PROCEDURE overwrite(n: INTEGER); BEGIN n := 4; WRITELN(n) END;
FUNCTION fact(n: INTEGER): INTEGER;
BEGIN IF n <= 1 THEN BEGIN fact := 1; RETURN END; fact := n * fact(n - 1) END;
FUNCTION twice(n: INTEGER): INTEGER; BEGIN twice := n + n END;
PROCEDURE probe;
VAR x, u: INTEGER; b: BOOLEAN; c: CHAR;
BEGIN
  x := pick(-32768, TRUE, 'a'); WRITELN(x, ' ', pick(0, FALSE, CHR(0)));
  b := same(FALSE); c := letter('q'); WRITELN(ORD(b), c);
  {$INITCK-} ignore(u); overwrite(u); {$INITCK+}
  x := twice(twice(fact(4))); WRITELN(x, ' ', fact(7))
END;
BEGIN probe END.
{$INITCK-}
