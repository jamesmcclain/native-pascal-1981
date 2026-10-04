{$MATHCK-}
{ Every overflowing WORD64 SUCC/PRED/ABS/SQR wraps modulo 2^64 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM BuiltinWrap;
VAR a: WORD64;
BEGIN
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; WRITELN(SUCC(a));  { 18446744073709551616 - 18446744073709551616 = 0 }
  a := 0; WRITELN(PRED(a));                                                     { -1 + 18446744073709551616 = 18446744073709551615 }
  a := 4294967296; WRITELN(SQR(a));                                             { 18446744073709551616 - 18446744073709551616 = 0 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; WRITELN(SQR(a))    { 340282366920938463426481119284349108225 - 18446744073709551616 = 1 }
END.
