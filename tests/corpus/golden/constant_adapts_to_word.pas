{ DIALECT: extended }
{ A named integer constant (a predeclared maximum or a wide CONST) beside a
  WORD-family operand takes that operand's type, like a bare literal. }
PROGRAM ConstantAdaptsToWord(output);
CONST B = 70000; NEG = -5000000000;
VAR w: WORD; d: WORD32; u: WORD64; l: INTEGER32;
BEGIN
  w := 1; d := 1; u := 1; l := 1;
  WRITELN(w + MAXINT, ' ', MAXINT + w);
  WRITELN(d + MAXINT32, ' ', d + B, ' ', B + d);
  WRITELN(u + MAXINT64, ' ', MAXINT64 + u, ' ', u + (MAXINT64 - 1));
  u := u + MAXINT64 + MAXINT64; WRITELN(u);
  WRITELN(u > MAXINT64, ' ', d < B, ' ', l + MAXINT);
  { A constant wider than the operand widens the operand instead. }
  WRITELN(d + NEG, ' ', NEG + d, ' ', d < NEG)
END.
