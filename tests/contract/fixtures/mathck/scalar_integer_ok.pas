{ INTEGER results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Signed MIN is ordinary data. }
PROGRAM OverflowOk;
VAR a, b: INTEGER;
BEGIN
  a := 32766; b := 1; WRITELN(a + b);       { 32767 }
  a := -32767; b := 1; WRITELN(a - b);      { -32768 }
  a := -32767; b := -1; WRITELN(a + b);     { -32768 }
  a := -16384; b := 2; WRITELN(a * b);      { -32768 }
  a := 32767; b := -1; WRITELN(a * b);      { -32767 }
  a := -32768; b := 1; WRITELN(a * b);      { -32768 }
  a := -1; b := 32767; WRITELN(a - b);      { -32768 }
  a := -32768; b := 32767; WRITELN(a + b);  { -1 }
  a := -32768; b := -1; WRITELN(a MOD b);   { 0: remainder only, no quotient }
  a := -32768; b := 1; WRITELN(a DIV b);    { -32768 }
  a := -32767; b := -1; WRITELN(a DIV b);   { 32767 }
  a := -32768; b := 2; WRITELN(a DIV b);    { -16384 }
  a := -32768; b := 2; WRITELN(a MOD b);    { 0 }
  a := 32767; WRITELN(-a);                  { -32767 }
  a := -32767; WRITELN(-a);                 { 32767 }
  a := 0; WRITELN(-a)                       { 0 }
END.
