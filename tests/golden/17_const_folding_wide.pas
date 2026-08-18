PROGRAM ConstFoldingWide(OUTPUT);
CONST
  Base = 32000;
  Step = 1000;
  Scale = 2;
VAR
  i32: INTEGER32;
  w64: WORD64;
BEGIN
  i32 := Base + Step;
  w64 := SUCC(PRED(Base)) * Scale;
  WRITELN(i32, ' ', w64);
END.
