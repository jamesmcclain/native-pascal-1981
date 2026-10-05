{$MATHCK-}
{ Every overflowing INTEGER8 SUCC/PRED/ABS/SQR wraps modulo 2^8 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: INTEGER8;
BEGIN
  a := 127; WRITELN(SUCC(a));   { 128 - 256 = -128 }
  a := -128; WRITELN(PRED(a));  { -129 + 256 = 127 }
  a := -128; WRITELN(ABS(a));   { 128 - 256 = -128 }
  a := 12; WRITELN(SQR(a));     { 144 - 256 = -112 }
  a := -12; WRITELN(SQR(a));    { 144 - 256 = -112 }
  a := -128; WRITELN(SQR(a))    { 16384 - 256 = 0 }
END.
