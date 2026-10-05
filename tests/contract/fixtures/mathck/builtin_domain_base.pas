{$MATHCK+}{$RANGECK+}
PROGRAM Domain;
TYPE Color = (red, green, blue); Hue = green..blue; Small = 1..10;
  Top = 0..32767;
VAR c: Color; h: Hue; ch: CHAR; b: BOOLEAN; s: Small; t: Top; i: INTEGER;
BEGIN
  t := 32767; t := SUCC(t);
END.
