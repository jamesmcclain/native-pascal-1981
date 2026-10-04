PROGRAM Domain;
TYPE Color = (red, green, blue); Hue = green..blue; Small = 1..10;
  Top = 0..32767;
VAR c: Color; h: Hue; ch: CHAR; b: BOOLEAN; s: Small; t: Top; i: INTEGER;
BEGIN
  c := red; c := SUCC(c); WRITELN(ORD(c), ' ', ORD(PRED(c)));
  c := green; WRITELN(ORD(SUCC(c)), ' ', ORD(PRED(c)));
  h := blue; WRITELN(ORD(PRED(h)));
  ch := CHR(254); WRITELN(ORD(SUCC(ch)), ' ', SUCC('a'), PRED('b'));
  ch := CHR(1); WRITELN(ORD(PRED(ch)));
  b := FALSE; WRITELN(SUCC(b), ' ', PRED(SUCC(b)));
  s := 9; s := SUCC(s); WRITELN(s, ' ', PRED(s));
  t := 32766; t := SUCC(t); WRITELN(t);
END.
