{$MATHCK-}
{ Every overflowing INTEGER32 SUCC/PRED/ABS/SQR wraps modulo 2^32 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: INTEGER32;
BEGIN
  a := 2147483647; WRITELN(SUCC(a));   { 2147483648 - 4294967296 = -2147483648 }
  a := -2147483648; WRITELN(PRED(a));  { -2147483649 + 4294967296 = 2147483647 }
  a := -2147483648; WRITELN(ABS(a));   { 2147483648 - 4294967296 = -2147483648 }
  a := 46341; WRITELN(SQR(a));         { 2147488281 - 4294967296 = -2147479015 }
  a := -46341; WRITELN(SQR(a));        { 2147488281 - 4294967296 = -2147479015 }
  a := -2147483648; WRITELN(SQR(a))    { 4611686018427387904 - 4294967296 = 0 }
END.
