{$MATHCK-}
{ Every INTEGER8 overflow wraps modulo 2^8 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: INTEGER8;
BEGIN
  a := 127; b := 1; WRITELN(a + b);      { 128 - 256 = -128 }
  a := -128; b := -1; WRITELN(a + b);    { -129 + 256 = 127 }
  a := -128; b := 1; WRITELN(a - b);     { -129 + 256 = 127 }
  a := 127; b := -1; WRITELN(a - b);     { 128 - 256 = -128 }
  a := 127; b := 2; WRITELN(a * b);      { 254 - 256 = -2 }
  a := -128; b := -1; WRITELN(a * b);    { 128 - 256 = -128 }
  a := -128; b := -1; WRITELN(a DIV b);  { 128 - 256 = -128 }
  a := -128; WRITELN(-a)                 { 128 - 256 = -128 }
END.
