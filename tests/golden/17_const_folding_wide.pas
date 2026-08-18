PROGRAM ConstFoldingWide(OUTPUT);
CONST
  Base = 20;
  Step = 3;
  Scale = 2;
VAR
  w8: WORD8;
  i32: INTEGER32;
  w64: WORD64;
BEGIN
  w8 := Base + Step * Scale;
  i32 := (Base + Step * Scale - 2) DIV 4 + (Base + Step * Scale - 2) MOD 4;
  w64 := SUCC(PRED(Base)) * Scale;
  WRITELN(w8, ' ', i32, ' ', w64);
END.
