{$MATHCK-}
{ Every INTEGER overflow wraps modulo 2^16 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: INTEGER;
BEGIN
  a := 32767; b := 1; WRITELN(a + b);      { 32768 - 65536 = -32768 }
  a := -32768; b := -1; WRITELN(a + b);    { -32769 + 65536 = 32767 }
  a := -32768; b := 1; WRITELN(a - b);     { -32769 + 65536 = 32767 }
  a := 32767; b := -1; WRITELN(a - b);     { 32768 - 65536 = -32768 }
  a := 32767; b := 2; WRITELN(a * b);      { 65534 - 65536 = -2 }
  a := -32768; b := -1; WRITELN(a * b);    { 32768 - 65536 = -32768 }
  a := -32768; b := -1; WRITELN(a DIV b);  { 32768 - 65536 = -32768 }
  a := -32768; WRITELN(-a)                 { 32768 - 65536 = -32768 }
END.
