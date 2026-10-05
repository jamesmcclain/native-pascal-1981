{$MATHCK-}
{ Every overflowing INTEGER64 SUCC/PRED/ABS/SQR wraps modulo 2^64 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM BuiltinWrap;
VAR a: INTEGER64;
BEGIN
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; WRITELN(SUCC(a));  { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 0; WRITELN(PRED(a));          { -9223372036854775809 + 18446744073709551616 = 9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 0; WRITELN(ABS(a));           { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := 3037000500; WRITELN(SQR(a));                                             { 9223372037000250000 - 18446744073709551616 = -9223372036709301616 }
  a := -3037000500; WRITELN(SQR(a));                                            { 9223372037000250000 - 18446744073709551616 = -9223372036709301616 }
  a := -2147483648; a := a * 4294967296; a := a + 0; WRITELN(SQR(a))            { 85070591730234615865843651857942052864 - 18446744073709551616 = 0 }
END.
