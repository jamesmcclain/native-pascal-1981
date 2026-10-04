{ WORD64 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Only zero negates without overflow.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowOk;
VAR a, b: WORD64;
BEGIN
  a := 4294967295; a := a * 4294967296; a := a + 4294967294; b := 1; WRITELN(a + b);                                                     { 18446744073709551615 }
  a := 1; b := 1; WRITELN(a - b);                                                                                                        { 0 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 4294967295; b := b * 4294967296; b := b + 4294967295; WRITELN(a - b);  { 0 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 1; WRITELN(a * b);                                                     { 18446744073709551615 }
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; b := 2; WRITELN(a * b);                                                     { 18446744073709551614 }
  a := 0; b := 0; WRITELN(a + b);                                                                                                        { 0 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 1; WRITELN(a DIV b);                                                   { 18446744073709551615 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 2; WRITELN(a MOD b);                                                   { 1 }
  a := 0; WRITELN(-a)                                                                                                                    { 0 }
END.
