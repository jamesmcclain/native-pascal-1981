{ DIALECT: vintage extended }
{ A CONST formal is a read-only reference (IBM manual 10-10): besides a
  variable it accepts a literal, a named constant, a function result or
  any other expression, which is spilled to a private temporary whose
  address is passed. Covers CHAR, INTEGER, REAL, BOOLEAN, STRING and
  LSTRING formals, and a CONST formal forwarded to another. }
PROGRAM ConstActualExpr(OUTPUT);
CONST
  K = 'k';
  N = 42;
  R = 2.5;
TYPE
  Text6 = STRING(6);
  Line = LSTRING(8);
VAR
  i: INTEGER;
  s: Text6;
  l: Line;

PROCEDURE V(CONST c: CHAR);
BEGIN
  WRITELN(c)
END;

PROCEDURE P(CONST n: INTEGER);
BEGIN
  WRITELN(n)
END;

PROCEDURE Q(CONST r: REAL);
BEGIN
  WRITELN(r:6:2)
END;

PROCEDURE B(CONST b: BOOLEAN);
BEGIN
  WRITELN(b)
END;

PROCEDURE S6(CONST t: Text6);
BEGIN
  WRITELN(t)
END;

PROCEDURE L8(CONST t: Line);
BEGIN
  WRITELN(t, ' ', ORD(t.LEN))
END;

PROCEDURE Forward2(CONST n: INTEGER);
BEGIN
  P(n);
  P(n + 1)
END;

FUNCTION Twice(x: INTEGER): INTEGER;
BEGIN
  Twice := 2 * x
END;

FUNCTION Half: REAL;
BEGIN
  Half := 0.5
END;

BEGIN
  V('z');
  V(K);
  V(CHR(ORD('a') + 1));
  i := 7;
  P(N);
  P(i);
  P(i + 1);
  P(Twice(i));
  P(-i);
  P(3);
  Forward2(N);
  Q(R);
  Q(1.5 * 2);
  Q(Half);
  B(i > 3);
  B(TRUE);
  S6('abcdef');
  s := 'xyzxyz';
  S6(s);
  L8('bye');
  l := 'ab';
  L8(l)
END.
