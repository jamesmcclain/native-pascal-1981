PROGRAM callorder;
TYPE PI = ^INTEGER;
PROCEDURE cpair(VAR v: INTEGER; b: INTEGER) [C]; EXTERN;
PROCEDURE cptr(p: PI; b: INTEGER) [C]; EXTERN;
PROCEDURE cadr(a: ADRMEM; b: INTEGER) [C]; EXTERN;
PROCEDURE probe;
VAR x, y: INTEGER; q: PI;
BEGIN
  {$INITCK+}
  x := 4; cpair(x, x); WRITELN(x);
  NEW(q); q^ := 6; cptr(q, q^); WRITELN(q^);
  y := 8; cadr(ADR y, y); WRITELN(y)
  {$INITCK-}
END;
BEGIN probe END.
