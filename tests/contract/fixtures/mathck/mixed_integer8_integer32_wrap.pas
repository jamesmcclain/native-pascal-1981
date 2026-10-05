{$MATHCK-}
{ INTEGER8 op INTEGER32: every sampled combination whose exact result
  overflows INTEGER32 (same samples and order as mixed_integer8_integer32_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER8; gr: INTEGER32;
BEGIN
gl := -128; gr := -2147483648; WRITELN(gl + gr);
gl := -64; gr := -2147483648; WRITELN(gl + gr);
gl := -2; gr := -2147483648; WRITELN(gl + gr);
gl := -1; gr := -2147483648; WRITELN(gl + gr);
gl := 1; gr := 2147483647; WRITELN(gl + gr);
gl := 2; gr := 2147483647; WRITELN(gl + gr);
gl := 3; gr := 2147483647; WRITELN(gl + gr);
gl := 64; gr := 2147483647; WRITELN(gl + gr);
gl := 127; gr := 2147483647; WRITELN(gl + gr);
gl := -128; gr := 2147483647; WRITELN(gl - gr);
gl := -64; gr := 2147483647; WRITELN(gl - gr);
gl := -2; gr := 2147483647; WRITELN(gl - gr);
gl := 0; gr := -2147483648; WRITELN(gl - gr);
gl := 1; gr := -2147483648; WRITELN(gl - gr);
gl := 2; gr := -2147483648; WRITELN(gl - gr);
gl := 3; gr := -2147483648; WRITELN(gl - gr);
gl := 64; gr := -2147483648; WRITELN(gl - gr);
gl := 127; gr := -2147483648; WRITELN(gl - gr);
gl := -128; gr := -2147483648; WRITELN(gl * gr);
gl := -128; gr := -1073741824; WRITELN(gl * gr);
gl := -128; gr := 1073741824; WRITELN(gl * gr);
gl := -128; gr := 2147483647; WRITELN(gl * gr);
gl := -64; gr := -2147483648; WRITELN(gl * gr);
gl := -64; gr := -1073741824; WRITELN(gl * gr);
gl := -64; gr := 1073741824; WRITELN(gl * gr);
gl := -64; gr := 2147483647; WRITELN(gl * gr);
gl := -2; gr := -2147483648; WRITELN(gl * gr);
gl := -2; gr := -1073741824; WRITELN(gl * gr);
gl := -2; gr := 2147483647; WRITELN(gl * gr);
gl := -1; gr := -2147483648; WRITELN(gl * gr);
gl := 2; gr := -2147483648; WRITELN(gl * gr);
gl := 2; gr := 1073741824; WRITELN(gl * gr);
gl := 2; gr := 2147483647; WRITELN(gl * gr);
gl := 3; gr := -2147483648; WRITELN(gl * gr);
gl := 3; gr := -1073741824; WRITELN(gl * gr);
gl := 3; gr := 1073741824; WRITELN(gl * gr);
gl := 3; gr := 2147483647; WRITELN(gl * gr);
gl := 64; gr := -2147483648; WRITELN(gl * gr);
gl := 64; gr := -1073741824; WRITELN(gl * gr);
gl := 64; gr := 1073741824; WRITELN(gl * gr);
gl := 64; gr := 2147483647; WRITELN(gl * gr);
gl := 127; gr := -2147483648; WRITELN(gl * gr);
gl := 127; gr := -1073741824; WRITELN(gl * gr);
gl := 127; gr := 1073741824; WRITELN(gl * gr);
gl := 127; gr := 2147483647; WRITELN(gl * gr);
END.
