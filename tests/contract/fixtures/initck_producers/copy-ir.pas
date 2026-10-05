PROGRAM copyir;
PROCEDURE probe;
VAR x, y: INTEGER;
BEGIN {$INITCK-} x := 1; y := x END;
BEGIN probe END.
