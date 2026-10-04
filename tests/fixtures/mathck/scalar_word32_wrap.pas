{$MATHCK-}
{ Every WORD32 overflow wraps modulo 2^32 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: WORD32;
BEGIN
  a := 4294967295; b := 1; WRITELN(a + b);  { 4294967296 - 4294967296 = 0 }
  a := 0; b := 1; WRITELN(a - b);           { -1 + 4294967296 = 4294967295 }
  a := 4294967295; b := 2; WRITELN(a * b);  { 8589934590 - 4294967296 = 4294967294 }
  a := 1; WRITELN(-a);                      { -1 + 4294967296 = 4294967295 }
  a := 4294967295; WRITELN(-a)              { -4294967295 + 4294967296 = 1 }
END.
