{ WORD32 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Only zero negates without overflow. }
PROGRAM OverflowOk;
VAR a, b: WORD32;
BEGIN
  a := 4294967294; b := 1; WRITELN(a + b);           { 4294967295 }
  a := 1; b := 1; WRITELN(a - b);                    { 0 }
  a := 4294967295; b := 4294967295; WRITELN(a - b);  { 0 }
  a := 4294967295; b := 1; WRITELN(a * b);           { 4294967295 }
  a := 2147483647; b := 2; WRITELN(a * b);           { 4294967294 }
  a := 0; b := 0; WRITELN(a + b);                    { 0 }
  a := 4294967295; b := 1; WRITELN(a DIV b);         { 4294967295 }
  a := 4294967295; b := 2; WRITELN(a MOD b);         { 1 }
  a := 0; WRITELN(-a)                                { 0 }
END.
