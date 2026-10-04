{$MATHCK-}
{ Every overflowing WORD32 SUCC/PRED/ABS/SQR wraps modulo 2^32 under
  MATHCK-; each comment gives the exact result and its wrapped value.
  Also the IR input: plain add/sub/mul, no overflow intrinsic. }
PROGRAM BuiltinWrap;
VAR a: WORD32;
BEGIN
  a := 4294967295; WRITELN(SUCC(a));  { 4294967296 - 4294967296 = 0 }
  a := 0; WRITELN(PRED(a));           { -1 + 4294967296 = 4294967295 }
  a := 65536; WRITELN(SQR(a));        { 4294967296 - 4294967296 = 0 }
  a := 4294967295; WRITELN(SQR(a))    { 18446744065119617025 - 4294967296 = 1 }
END.
