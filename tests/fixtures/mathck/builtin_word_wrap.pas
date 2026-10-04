{$MATHCK-}
{ Every overflowing WORD SUCC/PRED/ABS/SQR wraps modulo 2^16 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: WORD;
BEGIN
  a := 65535; WRITELN(SUCC(a));  { 65536 - 65536 = 0 }
  a := 0; WRITELN(PRED(a));      { -1 + 65536 = 65535 }
  a := 256; WRITELN(SQR(a));     { 65536 - 65536 = 0 }
  a := 65535; WRITELN(SQR(a))    { 4294836225 - 65536 = 1 }
END.
