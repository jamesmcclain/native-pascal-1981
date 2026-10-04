{$MATHCK-}
{ INTEGER32 op INTEGER64: every sampled combination whose exact result
  overflows INTEGER64 (same samples and order as mixed_integer32_integer64_ok.pas). Under
  MATHCK- each wraps modulo 2^64; .out holds the wrapped values.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidth;
VAR gl: INTEGER32; gr: INTEGER64;
BEGIN
gl := -2147483648; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -1073741824; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := -1; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl + gr);
gl := 1; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 3; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 1073741824; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 2147483647; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := -2147483648; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := -1073741824; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := -2; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 0; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 1; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 2; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 3; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 1073741824; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 2147483647; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := -2147483648; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -2147483648; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -2147483648; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -2147483648; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := -1073741824; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -1073741824; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -1073741824; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := -1073741824; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
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
gl := 1073741824; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 1073741824; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 1073741824; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 1073741824; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 2147483647; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2147483647; gr := -1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2147483647; gr := 1073741824; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2147483647; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
END.
