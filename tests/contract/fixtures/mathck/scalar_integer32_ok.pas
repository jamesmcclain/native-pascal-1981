{ INTEGER32 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Signed MIN is ordinary data. }
PROGRAM OverflowOk;
VAR a, b: INTEGER32;
BEGIN
  a := 2147483646; b := 1; WRITELN(a + b);            { 2147483647 }
  a := -2147483647; b := 1; WRITELN(a - b);           { -2147483648 }
  a := -2147483647; b := -1; WRITELN(a + b);          { -2147483648 }
  a := -1073741824; b := 2; WRITELN(a * b);           { -2147483648 }
  a := 2147483647; b := -1; WRITELN(a * b);           { -2147483647 }
  a := -2147483648; b := 1; WRITELN(a * b);           { -2147483648 }
  a := -1; b := 2147483647; WRITELN(a - b);           { -2147483648 }
  a := -2147483648; b := 2147483647; WRITELN(a + b);  { -1 }
  a := -2147483648; b := -1; WRITELN(a MOD b);        { 0: remainder only, no quotient }
  a := -2147483648; b := 1; WRITELN(a DIV b);         { -2147483648 }
  a := -2147483647; b := -1; WRITELN(a DIV b);        { 2147483647 }
  a := -2147483648; b := 2; WRITELN(a DIV b);         { -1073741824 }
  a := -2147483648; b := 2; WRITELN(a MOD b);         { 0 }
  a := 2147483647; WRITELN(-a);                       { -2147483647 }
  a := -2147483647; WRITELN(-a);                      { 2147483647 }
  a := 0; WRITELN(-a)                                 { 0 }
END.
