PROGRAM ConstFoldingWide(OUTPUT);
CONST
  Base = 20;
  Step = 3;
  Scale = 2;
  Sum = Base + Step * Scale;
  Quotient = (Sum - 2) DIV 4;
  Remainder = (Sum - 2) MOD 4;
  Next = SUCC(Quotient);
  Previous = PRED(Next);
VAR
  w8: WORD8;
  i32: INTEGER32;
  w64: WORD64;
BEGIN
  w8 := Sum;
  i32 := Quotient + Remainder;
  w64 := SUCC(Previous) * Scale;
  WRITELN(w8, ' ', i32, ' ', w64);
END.
