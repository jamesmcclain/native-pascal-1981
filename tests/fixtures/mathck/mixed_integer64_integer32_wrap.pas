{$MATHCK-}
{ INTEGER64 op INTEGER32: every sampled combination whose exact result
  overflows INTEGER64 (same samples and order as mixed_integer64_integer32_ok.pas). Under
  MATHCK- each wraps modulo 2^64; .out holds the wrapped values.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidth;
VAR gl: INTEGER64; gr: INTEGER32;
BEGIN
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -2147483648; WRITELN(gl + gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1073741824; WRITELN(gl + gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -2; WRITELN(gl + gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1; WRITELN(gl + gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1; WRITELN(gl + gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2; WRITELN(gl + gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 3; WRITELN(gl + gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1073741824; WRITELN(gl + gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2147483647; WRITELN(gl + gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 1; WRITELN(gl - gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2; WRITELN(gl - gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 3; WRITELN(gl - gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 1073741824; WRITELN(gl - gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2147483647; WRITELN(gl - gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -2147483648; WRITELN(gl - gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -1073741824; WRITELN(gl - gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -2; WRITELN(gl - gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -1; WRITELN(gl - gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -2147483648; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1073741824; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -2; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 3; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 1073741824; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2147483647; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := -2147483648; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := -1073741824; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := -2; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 3; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 1073741824; WRITELN(gl * gr);
gl := -1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 2147483647; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := -2147483648; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := -1073741824; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 2; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 3; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 1073741824; WRITELN(gl * gr);
gl := 1073741824; gl := gl * 4294967296; gl := gl + 0; gr := 2147483647; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -2147483648; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -1073741824; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -2; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 3; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1073741824; WRITELN(gl * gr);
gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2147483647; WRITELN(gl * gr);
gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1; WRITELN(gl DIV gr);
END.
