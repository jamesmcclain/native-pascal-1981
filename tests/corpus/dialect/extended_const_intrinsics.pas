{ DIALECT: extended }
PROGRAM ExtendedConstIntrinsics(OUTPUT);
CONST
  base = 65;
  initial = cHr(base);
  next = ChR(sUcC(oRd(initial)));
  previous = pReD(oRd(next));
VAR
  c: CHAR;
BEGIN
  c := next;
  WRITELN(initial);
  WRITELN(c);
  WRITELN(previous)
END.
