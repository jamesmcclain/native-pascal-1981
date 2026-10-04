PROGRAM varir;
VAR g: INTEGER;
PROCEDURE bump(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END;
PROCEDURE probe;
VAR x: INTEGER;
BEGIN x := 1; bump(x); bump(g) END;
BEGIN probe END.
