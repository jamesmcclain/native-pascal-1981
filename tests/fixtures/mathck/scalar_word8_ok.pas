{ WORD8 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Only zero negates without overflow. }
PROGRAM OverflowOk;
VAR a, b: WORD8;
BEGIN
  a := 254; b := 1; WRITELN(a + b);    { 255 }
  a := 1; b := 1; WRITELN(a - b);      { 0 }
  a := 255; b := 255; WRITELN(a - b);  { 0 }
  a := 255; b := 1; WRITELN(a * b);    { 255 }
  a := 127; b := 2; WRITELN(a * b);    { 254 }
  a := 0; b := 0; WRITELN(a + b);      { 0 }
  a := 255; b := 1; WRITELN(a DIV b);  { 255 }
  a := 255; b := 2; WRITELN(a MOD b);  { 1 }
  a := 0; WRITELN(-a)                  { 0 }
END.
