{$MATHCK-}
{ Every WORD overflow wraps modulo 2^16 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: WORD;
BEGIN
  a := 65535; b := 1; WRITELN(a + b);  { 65536 - 65536 = 0 }
  a := 0; b := 1; WRITELN(a - b);      { -1 + 65536 = 65535 }
  a := 65535; b := 2; WRITELN(a * b);  { 131070 - 65536 = 65534 }
  a := 1; WRITELN(-a);                 { -1 + 65536 = 65535 }
  a := 65535; WRITELN(-a)              { -65535 + 65536 = 1 }
END.
