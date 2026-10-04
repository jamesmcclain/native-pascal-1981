{$MATHCK-}
{ Every overflowing INTEGER SUCC/PRED/ABS/SQR wraps modulo 2^16 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: INTEGER;
BEGIN
  a := 32767; WRITELN(SUCC(a));   { 32768 - 65536 = -32768 }
  a := -32768; WRITELN(PRED(a));  { -32769 + 65536 = 32767 }
  a := -32768; WRITELN(ABS(a));   { 32768 - 65536 = -32768 }
  a := 182; WRITELN(SQR(a));      { 33124 - 65536 = -32412 }
  a := -182; WRITELN(SQR(a));     { 33124 - 65536 = -32412 }
  a := -32768; WRITELN(SQR(a))    { 1073741824 - 65536 = 0 }
END.
