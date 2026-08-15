PROGRAM Arithmetic(OUTPUT);
VAR
  a, b, c: INTEGER;
BEGIN
  a := 10;
  b := 25;
  c := a + b * 2 - 5;
  WRITELN('c = ', c);
  WRITELN('div = ', b DIV a, ' mod = ', b MOD a);
END.
