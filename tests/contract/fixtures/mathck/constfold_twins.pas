{ Constant DIV/MOD truncates toward zero and MOD takes the dividend's
  sign, in the compile-time folder and at run time alike. Each row appears
  twice: k := (a) op (b) is folded as a constant, then the same operands go
  through variables. Rows (a, b): (-7, 2) (7, -2) (-7, -2) (7, 2) (-8, 2)
  (0, -2) (-32768, -1), DIV then MOD; -32768 DIV -1 is left out because its
  exact result 32768 does not fit INTEGER. .out holds both values of each
  row. The suite prepends the MATHCK+ or MATHCK- directive; the result is
  the same. }
PROGRAM FoldProbe;
VAR a, b, k: INTEGER;
BEGIN
k := (-7) DIV (2); WRITELN(k);
a := -7; b := 2; WRITELN(a DIV b);
k := (-7) MOD (2); WRITELN(k);
a := -7; b := 2; WRITELN(a MOD b);
k := (7) DIV (-2); WRITELN(k);
a := 7; b := -2; WRITELN(a DIV b);
k := (7) MOD (-2); WRITELN(k);
a := 7; b := -2; WRITELN(a MOD b);
k := (-7) DIV (-2); WRITELN(k);
a := -7; b := -2; WRITELN(a DIV b);
k := (-7) MOD (-2); WRITELN(k);
a := -7; b := -2; WRITELN(a MOD b);
k := (7) DIV (2); WRITELN(k);
a := 7; b := 2; WRITELN(a DIV b);
k := (7) MOD (2); WRITELN(k);
a := 7; b := 2; WRITELN(a MOD b);
k := (-8) DIV (2); WRITELN(k);
a := -8; b := 2; WRITELN(a DIV b);
k := (-8) MOD (2); WRITELN(k);
a := -8; b := 2; WRITELN(a MOD b);
k := (0) DIV (-2); WRITELN(k);
a := 0; b := -2; WRITELN(a DIV b);
k := (0) MOD (-2); WRITELN(k);
a := 0; b := -2; WRITELN(a MOD b);
k := (-32768) MOD (-1); WRITELN(k);
a := -32768; b := -1; WRITELN(a MOD b);
END.
