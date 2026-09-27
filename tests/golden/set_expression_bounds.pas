{ DIALECT: extended }
{ LOWER/UPPER of a set union, intersection or difference keep the operands'
  base type when they share one, with bounds covering both declared ranges.
  A set constructor has no declared bounds, so mixing one in gives the
  generic INTEGER set bounds, 0..255. Incompatible declared bases are
  rejected; generic bounds do not make them compatible. }
PROGRAM SetExpressionBounds(output);
TYPE BoolSet = SET OF BOOLEAN; CS = SET OF CHAR; A = SET OF 3..9; B = SET OF 1..5;
     Rec = RECORD cs: CS END;
VAR bs, bt: BoolSet; cs: CS; a: A; b: B; r: Rec; f: BOOLEAN; c: CHAR; i: INTEGER;
FUNCTION getb(n: INTEGER): BoolSet; BEGIN getb := bs END;
BEGIN
  WRITELN(LOWER(bs + bs), ' ', UPPER(bs * bt), ' ', UPPER(bs - getb(0)));
  WRITELN(ORD(LOWER(cs + r.cs)), ' ', ORD(UPPER((cs + cs) * r.cs)));
  WRITELN(LOWER(a + b), ' ', UPPER(a + b), ' ', LOWER(a * a), ' ', UPPER(a - a));
  WRITELN(LOWER(bs + [TRUE]), ' ', UPPER(a + [1]), ' ', UPPER(cs + ['A']));
  f := UPPER(bs + bt); c := LOWER(cs * cs); i := UPPER(a + b);
  WRITELN(f, ' ', ORD(c), ' ', i)
END.
