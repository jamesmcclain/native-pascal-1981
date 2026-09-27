PROGRAM SetBaseComparisonRejected(OUTPUT);
VAR
  s: SET OF 0..9;
  bs: SET OF BOOLEAN;
BEGIN
  WRITELN(bs = [0]);
  WRITELN([0] = bs);
  WRITELN(bs = [1]);
  WRITELN([1] = bs);
  WRITELN(bs <> s);
  WRITELN(s = bs);
  WRITELN(bs < s);
  WRITELN(s <= bs);
  WRITELN(bs > s);
  WRITELN(s >= bs)
END.
