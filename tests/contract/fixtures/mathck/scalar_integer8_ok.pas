{ INTEGER8 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Signed MIN is ordinary data. }
PROGRAM OverflowOk;
VAR a, b: INTEGER8;
BEGIN
  a := 126; b := 1; WRITELN(a + b);      { 127 }
  a := -127; b := 1; WRITELN(a - b);     { -128 }
  a := -127; b := -1; WRITELN(a + b);    { -128 }
  a := -64; b := 2; WRITELN(a * b);      { -128 }
  a := 127; b := -1; WRITELN(a * b);     { -127 }
  a := -128; b := 1; WRITELN(a * b);     { -128 }
  a := -1; b := 127; WRITELN(a - b);     { -128 }
  a := -128; b := 127; WRITELN(a + b);   { -1 }
  a := -128; b := -1; WRITELN(a MOD b);  { 0: remainder only, no quotient }
  a := -128; b := 1; WRITELN(a DIV b);   { -128 }
  a := -127; b := -1; WRITELN(a DIV b);  { 127 }
  a := -128; b := 2; WRITELN(a DIV b);   { -64 }
  a := -128; b := 2; WRITELN(a MOD b);   { 0 }
  a := 127; WRITELN(-a);                 { -127 }
  a := -127; WRITELN(-a);                { 127 }
  a := 0; WRITELN(-a)                    { 0 }
END.
