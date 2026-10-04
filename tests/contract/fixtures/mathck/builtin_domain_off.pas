PROGRAM Domain;
TYPE Color = (red, green, blue); Hue = green..blue; Small = 1..10;
  Top = 0..32767;
VAR c: Color; h: Hue; ch: CHAR; b: BOOLEAN; s: Small; t: Top; i: INTEGER;
BEGIN
  ch := CHR(255); WRITELN(ORD(SUCC(ch)));
  ch := CHR(0); WRITELN(ORD(PRED(ch)));
  s := 10; i := SUCC(s); WRITELN(i);
END.
