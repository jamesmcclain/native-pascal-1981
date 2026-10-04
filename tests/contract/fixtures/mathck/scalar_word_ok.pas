{ WORD results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Only zero negates without overflow. }
PROGRAM OverflowOk;
VAR a, b: WORD;
BEGIN
  a := 65534; b := 1; WRITELN(a + b);      { 65535 }
  a := 1; b := 1; WRITELN(a - b);          { 0 }
  a := 65535; b := 65535; WRITELN(a - b);  { 0 }
  a := 65535; b := 1; WRITELN(a * b);      { 65535 }
  a := 32767; b := 2; WRITELN(a * b);      { 65534 }
  a := 0; b := 0; WRITELN(a + b);          { 0 }
  a := 65535; b := 1; WRITELN(a DIV b);    { 65535 }
  a := 65535; b := 2; WRITELN(a MOD b);    { 1 }
  a := 0; WRITELN(-a)                      { 0 }
END.
