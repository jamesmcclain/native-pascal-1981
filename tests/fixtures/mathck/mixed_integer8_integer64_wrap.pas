{$MATHCK-}
{ INTEGER8 op INTEGER64: every sampled combination whose exact result
  overflows INTEGER64 (same samples and order as mixed_integer8_integer64_ok.pas). Under
  MATHCK- each wraps modulo 2^64; .out holds the wrapped values.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidth;
VAR gl: INTEGER8; gr: INTEGER64;
BEGIN
gl := -128; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -64; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -1; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := 1; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 3; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 64; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 127; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := -128; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := -64; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := -2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 0; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 1; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 3; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 64; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 127; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := -128; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -128; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -128; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -128; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := -64; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -64; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -64; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -64; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := -2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -2; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := -1; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 3; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 3; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 3; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 3; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 64; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 64; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 64; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 64; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 127; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 127; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 127; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 127; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
END.
