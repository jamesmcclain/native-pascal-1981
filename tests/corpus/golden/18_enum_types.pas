PROGRAM enumtypes(output);
{ User-declared enumerated types: members are compile-time ordinal
  constants, storage is the ordinal as INTEGER32, WRITE prints the ordinal
  (the vintage default), and the ordinal builtins plus FOR all treat the
  value as an ordinal -- matching the Python reference's default behavior
  and the manual's read-as-number rule (13610-13618). }
TYPE
  hue = (red, green, blue);
VAR
  c, d: hue;
BEGIN
  c := green;
  WRITELN('ord=', ORD(c));
  WRITELN('write=', c);
  c := SUCC(c);
  WRITELN('succ=', ORD(c));
  c := PRED(c);
  IF c = green THEN WRITELN('back to green');
  d := blue;
  IF d > c THEN WRITELN('blue > green');
  FOR c := red TO blue DO WRITELN('for ', ORD(c));
END.
