{ WORD64 SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(18446744073709551615) = 4294967295. A WORD-family ABS is its argument.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM BuiltinOk;
VAR a: WORD64;
BEGIN
  a := 4294967295; a := a * 4294967296; a := a + 4294967294; WRITELN(SUCC(a));  { 18446744073709551615 }
  a := 1; WRITELN(PRED(a));                                                     { 0 }
  a := 0; WRITELN(SUCC(a));                                                     { 1 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; WRITELN(PRED(a));  { 18446744073709551614 }
  a := 0; WRITELN(SUCC(a));                                                     { 1 }
  a := 1; WRITELN(PRED(a));                                                     { 0 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; WRITELN(ABS(a));   { 18446744073709551615 }
  a := 0; WRITELN(ABS(a));                                                      { 0 }
  a := 4294967295; WRITELN(SQR(a));                                             { 18446744065119617025 }
  a := 0; WRITELN(SQR(a));                                                      { 0 }
  a := 1; WRITELN(SQR(a));                                                      { 1 }
  a := 2147483648; a := a * 4294967296; a := a + 0; WRITELN(ABS(a));            { 9223372036854775808 }
  a := 1; WRITELN(ABS(a))                                                       { 1 }
END.
