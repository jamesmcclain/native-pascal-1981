{ INTEGER64 results at the boundaries that fit: identical under MATHCK+ and
  MATHCK- (the suite prepends the directive). Operands are assigned at run
  time; each comment gives the exact result. Signed MIN is ordinary data.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowOk;
VAR a, b: INTEGER64;
BEGIN
  a := 2147483647; a := a * 4294967296; a := a + 4294967294; b := 1; WRITELN(a + b);                                             { 9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 1; b := 1; WRITELN(a - b);                                                     { -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 1; b := -1; WRITELN(a + b);                                                    { -9223372036854775808 }
  a := -1073741824; a := a * 4294967296; a := a + 0; b := 2; WRITELN(a * b);                                                     { -9223372036854775808 }
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; b := -1; WRITELN(a * b);                                            { -9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 1; WRITELN(a * b);                                                     { -9223372036854775808 }
  a := -1; b := 2147483647; b := b * 4294967296; b := b + 4294967295; WRITELN(a - b);                                            { -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 2147483647; b := b * 4294967296; b := b + 4294967295; WRITELN(a + b);  { -1 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := -1; WRITELN(a MOD b);                                                  { 0: remainder only, no quotient }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 1; WRITELN(a DIV b);                                                   { -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 1; b := -1; WRITELN(a DIV b);                                                  { 9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 2; WRITELN(a DIV b);                                                   { -4611686018427387904 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 2; WRITELN(a MOD b);                                                   { 0 }
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; WRITELN(-a);                                                        { -9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 1; WRITELN(-a);                                                                { 9223372036854775807 }
  a := 0; WRITELN(-a)                                                                                                            { 0 }
END.
