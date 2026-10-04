{$MATHCK-}
{ Every WORD64 overflow wraps modulo 2^64 under MATHCK-. Each comment
  gives the exact result and its wrapped value. Also the IR-shape input:
  plain add/sub/mul with no overflow intrinsic, nsw/nuw, poison or undef.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowWrap;
VAR a, b: WORD64;
BEGIN
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 1; WRITELN(a + b);  { 18446744073709551616 - 18446744073709551616 = 0 }
  a := 0; b := 1; WRITELN(a - b);                                                     { -1 + 18446744073709551616 = 18446744073709551615 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; b := 2; WRITELN(a * b);  { 36893488147419103230 - 18446744073709551616 = 18446744073709551614 }
  a := 1; WRITELN(-a);                                                                { -1 + 18446744073709551616 = 18446744073709551615 }
  a := 4294967295; a := a * 4294967296; a := a + 4294967295; WRITELN(-a)              { -18446744073709551615 + 18446744073709551616 = 1 }
END.
