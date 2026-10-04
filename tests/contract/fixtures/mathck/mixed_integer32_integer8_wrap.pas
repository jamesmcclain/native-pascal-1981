{$MATHCK-}
{ INTEGER32 op INTEGER8: every sampled combination whose exact result
  overflows INTEGER32 (same samples and order as mixed_integer32_integer8_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER32; gr: INTEGER8;
BEGIN
gl := -2147483648; gr := -128; WRITELN(gl + gr);
gl := -2147483648; gr := -64; WRITELN(gl + gr);
gl := -2147483648; gr := -2; WRITELN(gl + gr);
gl := -2147483648; gr := -1; WRITELN(gl + gr);
gl := 2147483647; gr := 1; WRITELN(gl + gr);
gl := 2147483647; gr := 2; WRITELN(gl + gr);
gl := 2147483647; gr := 3; WRITELN(gl + gr);
gl := 2147483647; gr := 64; WRITELN(gl + gr);
gl := 2147483647; gr := 127; WRITELN(gl + gr);
gl := -2147483648; gr := 1; WRITELN(gl - gr);
gl := -2147483648; gr := 2; WRITELN(gl - gr);
gl := -2147483648; gr := 3; WRITELN(gl - gr);
gl := -2147483648; gr := 64; WRITELN(gl - gr);
gl := -2147483648; gr := 127; WRITELN(gl - gr);
gl := 2147483647; gr := -128; WRITELN(gl - gr);
gl := 2147483647; gr := -64; WRITELN(gl - gr);
gl := 2147483647; gr := -2; WRITELN(gl - gr);
gl := 2147483647; gr := -1; WRITELN(gl - gr);
gl := -2147483648; gr := -128; WRITELN(gl * gr);
gl := -2147483648; gr := -64; WRITELN(gl * gr);
gl := -2147483648; gr := -2; WRITELN(gl * gr);
gl := -2147483648; gr := -1; WRITELN(gl * gr);
gl := -2147483648; gr := 2; WRITELN(gl * gr);
gl := -2147483648; gr := 3; WRITELN(gl * gr);
gl := -2147483648; gr := 64; WRITELN(gl * gr);
gl := -2147483648; gr := 127; WRITELN(gl * gr);
gl := -1073741824; gr := -128; WRITELN(gl * gr);
gl := -1073741824; gr := -64; WRITELN(gl * gr);
gl := -1073741824; gr := -2; WRITELN(gl * gr);
gl := -1073741824; gr := 3; WRITELN(gl * gr);
gl := -1073741824; gr := 64; WRITELN(gl * gr);
gl := -1073741824; gr := 127; WRITELN(gl * gr);
gl := 1073741824; gr := -128; WRITELN(gl * gr);
gl := 1073741824; gr := -64; WRITELN(gl * gr);
gl := 1073741824; gr := 2; WRITELN(gl * gr);
gl := 1073741824; gr := 3; WRITELN(gl * gr);
gl := 1073741824; gr := 64; WRITELN(gl * gr);
gl := 1073741824; gr := 127; WRITELN(gl * gr);
gl := 2147483647; gr := -128; WRITELN(gl * gr);
gl := 2147483647; gr := -64; WRITELN(gl * gr);
gl := 2147483647; gr := -2; WRITELN(gl * gr);
gl := 2147483647; gr := 2; WRITELN(gl * gr);
gl := 2147483647; gr := 3; WRITELN(gl * gr);
gl := 2147483647; gr := 64; WRITELN(gl * gr);
gl := 2147483647; gr := 127; WRITELN(gl * gr);
gl := -2147483648; gr := -1; WRITELN(gl DIV gr);
END.
