PROGRAM routines;
TYPE
  Pair = RECORD a, b: INTEGER END;
  Big = RECORD a, b, c, d, e, f, g, h, i, j: INTEGER END;
  PInt = ^INTEGER;
FUNCTION echo(i: INTEGER; b: BOOLEAN; c: CHAR): INTEGER;
VAR t: INTEGER; u: BOOLEAN;
BEGIN
  t := i; u := b;
  {$INITCK+} IF u THEN echo := t ELSE {$INITCK-} echo := ORD(c)
END;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; {$INITCK+} y := t {$INITCK-} END;
PROCEDURE view(CONST c: CHAR; CONST p: Pair);
BEGIN WRITELN(ORD(c), ' ', p.a, ' ', p.b) END;
FUNCTION noint: INTEGER; BEGIN END;
FUNCTION nobool: BOOLEAN; BEGIN END;
FUNCTION nochar: CHAR; BEGIN END;
FUNCTION noreal: REAL; BEGIN END;
FUNCTION noptr: PInt; BEGIN END;
FUNCTION nopair: Pair; BEGIN END;
FUNCTION nobig: Big; BEGIN END;
FUNCTION early(n: INTEGER): INTEGER;
BEGIN IF n > 0 THEN BEGIN early := n; {$INITCK+} RETURN END {$INITCK-} END;
FUNCTION fact(n: INTEGER): INTEGER;
BEGIN IF n <= 1 THEN fact := 1 ELSE fact := n * fact(n - 1) END;
PROCEDURE outer(n: INTEGER);
VAR m: INTEGER;
  FUNCTION inner(k: INTEGER): INTEGER;
  BEGIN inner := k + 1 END;
BEGIN m := inner(n); WRITELN(m) END;
VAR x, y: INTEGER; p: Pair; bg: Big; ch: CHAR;
BEGIN
  {$INITCK-}
  WRITELN(echo(-32768, TRUE, 'a'), ' ', echo(0, FALSE, CHR(0)));
  x := 1; y := -32768; swap(x, y); WRITELN(x, ' ', y);
  p.a := 3; p.b := 4; ch := 'z'; view(ch, p);
  WRITELN(noint, ' ', ORD(nobool), ' ', ORD(nochar), ' ', noreal:3:1, ' ', noptr = NIL);
  p := nopair; bg := nobig; WRITELN(p.a, ' ', p.b, ' ', bg.a, ' ', bg.j);
  WRITELN(early(0), ' ', early(5), ' ', fact(5));
  outer(41)
END.
