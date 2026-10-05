PROGRAM recvarok;
{$INITCK+}
PROCEDURE fill(VAR n: INTEGER; d: INTEGER);
BEGIN IF d = 0 THEN n := 5 ELSE BEGIN fill(n, d - 1); n := n + 1 END END;
PROCEDURE probe; VAR x: INTEGER; BEGIN fill(x, 3); WRITELN(x) END;
BEGIN probe END.
{$INITCK-}
