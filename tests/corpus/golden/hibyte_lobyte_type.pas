{ DIALECT: vintage }
{ HIBYTE and LOBYTE return the byte 0..255 with the argument's own
  type, INTEGER or WORD, as in the IBM manual. }
PROGRAM hib(OUTPUT);
VAR i, k: INTEGER; w: WORD;
BEGIN
  i := 16#1234; w := 16#ABCD;
  k := HIBYTE(i) * 256 + LOBYTE(i);
  WRITELN(HIBYTE(i), ' ', LOBYTE(i), ' ', k);
  w := HIBYTE(w) + LOBYTE(w);
  WRITELN(w);
  i := -1;
  WRITELN(HIBYTE(i), ' ', LOBYTE(i));
  WRITELN(CHR(LOBYTE(65)))
END.
