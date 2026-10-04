{$MATHCK-}
{ Every INTEGER32 overflow wraps modulo 2^32 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef. }
PROGRAM OverflowWrap;
VAR a, b: INTEGER32;
BEGIN
  a := 2147483647; b := 1; WRITELN(a + b);      { 2147483648 - 4294967296 = -2147483648 }
  a := -2147483648; b := -1; WRITELN(a + b);    { -2147483649 + 4294967296 = 2147483647 }
  a := -2147483648; b := 1; WRITELN(a - b);     { -2147483649 + 4294967296 = 2147483647 }
  a := 2147483647; b := -1; WRITELN(a - b);     { 2147483648 - 4294967296 = -2147483648 }
  a := 2147483647; b := 2; WRITELN(a * b);      { 4294967294 - 4294967296 = -2 }
  a := -2147483648; b := -1; WRITELN(a * b);    { 2147483648 - 4294967296 = -2147483648 }
  a := -2147483648; b := -1; WRITELN(a DIV b);  { 2147483648 - 4294967296 = -2147483648 }
  a := -2147483648; WRITELN(-a)                 { 2147483648 - 4294967296 = -2147483648 }
END.
