{ DIALECT: extended }
{ A value read from a subrange variable is a value of the host type, so it
  mixes with host-type operands, indexes arrays, and drives FOR loops. }
PROGRAM SubrangeValues(OUTPUT);
TYPE
  Color = (Red, Green, Blue, Yellow);
  Small = 1..10;
VAR
  x: Small;
  i: INTEGER;
  a: ARRAY[1..10] OF INTEGER;
  c: 'a'..'z';
  s: Green..Yellow;
  f: FALSE..TRUE;

FUNCTION Next(y: Small): Small;
BEGIN
  Next := y + 1
END;

BEGIN
  x := 3;
  WRITELN(x + 1, x * 2 - x, -x, x < 5, ODD(x));
  FOR x := 1 TO 3 DO a[x] := x * 10;
  x := 2;
  WRITELN(a[x], a[x + 1]);
  i := Next(x);
  x := Next(x);
  WRITELN(i, x, UPPER(x) - LOWER(x));
  CASE x OF
    3: WRITELN('three');
    4: WRITELN('four')
  END;
  c := 'q';
  WRITELN(c < 'm', ORD(c), SUCC(c));
  s := Blue;
  WRITELN(ORD(s), s > Green, s = Blue);
  FOR s := Green TO Yellow DO WRITE(ORD(s));
  WRITELN;
  f := TRUE;
  WRITELN(f AND (x > 0))
END.
