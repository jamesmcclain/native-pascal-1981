{$MATHCK-}
{ Every WORD8 overflow wraps modulo 2^8 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: WORD8;
BEGIN
  a := 255; b := 1; WRITELN(a + b);  { 256 - 256 = 0 }
  a := 0; b := 1; WRITELN(a - b);    { -1 + 256 = 255 }
  a := 255; b := 2; WRITELN(a * b);  { 510 - 256 = 254 }
  a := 1; WRITELN(-a);               { -1 + 256 = 255 }
  a := 255; WRITELN(-a)              { -255 + 256 = 1 }
END.
