{$MATHCK-}
{ Every INTEGER64 overflow wraps modulo 2^64 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowWrap;
VAR a, b: INTEGER64;
BEGIN
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; b := 1; WRITELN(a + b);   { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := -1; WRITELN(a + b);          { -9223372036854775809 + 18446744073709551616 = 9223372036854775807 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := 1; WRITELN(a - b);           { -9223372036854775809 + 18446744073709551616 = 9223372036854775807 }
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; b := -1; WRITELN(a - b);  { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := 2147483647; a := a * 4294967296; a := a + 4294967295; b := 2; WRITELN(a * b);   { 18446744073709551614 - 18446744073709551616 = -2 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := -1; WRITELN(a * b);          { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 0; b := -1; WRITELN(a DIV b);        { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
  a := -2147483648; a := a * 4294967296; a := a + 0; WRITELN(-a)                       { 9223372036854775808 - 18446744073709551616 = -9223372036854775808 }
END.
