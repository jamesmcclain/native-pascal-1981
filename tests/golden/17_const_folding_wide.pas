PROGRAM ConstFoldingWide(OUTPUT);
CONST
  Base = 32000;
  Step = 1000;
  Scale = 2;
  Negative = -5;
VAR
  i32, floor_div, floor_mod: INTEGER32;
  w64: WORD64;
BEGIN
  i32 := Base + Step;
  w64 := SUCC(PRED(Base)) * Scale;
  floor_div := Negative DIV Scale;
  floor_mod := Negative MOD Scale;
  WRITELN(i32, ' ', w64, ' ', floor_div, ' ', floor_mod);
END.
