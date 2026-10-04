{$MATHCK-}
{ Every overflowing WORD8 SUCC/PRED/ABS/SQR wraps modulo 2^8 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: WORD8;
BEGIN
  a := 255; WRITELN(SUCC(a));  { 256 - 256 = 0 }
  a := 0; WRITELN(PRED(a));    { -1 + 256 = 255 }
  a := 16; WRITELN(SQR(a));    { 256 - 256 = 0 }
  a := 255; WRITELN(SQR(a))    { 65025 - 256 = 1 }
END.
