PROGRAM cwrite;
TYPE A2 = ARRAY [1..2] OF CHAR; PI = ^INTEGER;
PROCEDURE cset(VAR v: INTEGER) [C]; EXTERN;
PROCEDURE cfill(VAR v: A2) [C]; EXTERN;
PROCEDURE cpeek(CONST v: INTEGER) [C]; EXTERN;
PROCEDURE pset(VAR v: INTEGER); EXTERN;
PROCEDURE pwrite(p: PI); EXTERN;
PROCEDURE relay(VAR v: INTEGER); EXTERN;
FUNCTION cval: INTEGER; EXTERN;
PROCEDURE cb(VAR n: INTEGER); BEGIN {$INITCK+} n := n + 1 {$INITCK-} END;
FUNCTION unsetres: INTEGER; BEGIN END;
PROCEDURE probe;
VAR x, y, z, w, k: INTEGER; a: A2; m: ARRAY [1..2] OF INTEGER; q: PI;
BEGIN
  {$INITCK+}
  cset(x); WRITELN(x);
  cfill(a); WRITELN(a[1], a[2]);
  m[1] := 1; cset(m[2]); WRITELN(m[1] + m[2]);
  k := 3; cpeek(k); WRITELN(k);
  pset(y); WRITELN(y);
  relay(z); WRITELN(z);
  w := cval; WRITELN(w);
  NEW(q); pwrite(q); WRITELN(q^)
  {$INITCK-}
END;
BEGIN probe END.
