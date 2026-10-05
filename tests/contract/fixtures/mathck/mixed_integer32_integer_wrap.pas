{$MATHCK-}
{ INTEGER32 op INTEGER: every sampled combination whose exact result
  overflows INTEGER32 (same samples and order as mixed_integer32_integer_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER32; gr: INTEGER;
BEGIN
gl := -2147483648; gr := -32768; WRITELN(gl + gr);
gl := -2147483648; gr := -16384; WRITELN(gl + gr);
gl := -2147483648; gr := -2; WRITELN(gl + gr);
gl := -2147483648; gr := -1; WRITELN(gl + gr);
gl := 2147483647; gr := 1; WRITELN(gl + gr);
gl := 2147483647; gr := 2; WRITELN(gl + gr);
gl := 2147483647; gr := 3; WRITELN(gl + gr);
gl := 2147483647; gr := 16384; WRITELN(gl + gr);
gl := 2147483647; gr := 32767; WRITELN(gl + gr);
gl := -2147483648; gr := 1; WRITELN(gl - gr);
gl := -2147483648; gr := 2; WRITELN(gl - gr);
gl := -2147483648; gr := 3; WRITELN(gl - gr);
gl := -2147483648; gr := 16384; WRITELN(gl - gr);
gl := -2147483648; gr := 32767; WRITELN(gl - gr);
gl := 2147483647; gr := -32768; WRITELN(gl - gr);
gl := 2147483647; gr := -16384; WRITELN(gl - gr);
gl := 2147483647; gr := -2; WRITELN(gl - gr);
gl := 2147483647; gr := -1; WRITELN(gl - gr);
gl := -2147483648; gr := -32768; WRITELN(gl * gr);
gl := -2147483648; gr := -16384; WRITELN(gl * gr);
gl := -2147483648; gr := -2; WRITELN(gl * gr);
gl := -2147483648; gr := -1; WRITELN(gl * gr);
gl := -2147483648; gr := 2; WRITELN(gl * gr);
gl := -2147483648; gr := 3; WRITELN(gl * gr);
gl := -2147483648; gr := 16384; WRITELN(gl * gr);
gl := -2147483648; gr := 32767; WRITELN(gl * gr);
gl := -1073741824; gr := -32768; WRITELN(gl * gr);
gl := -1073741824; gr := -16384; WRITELN(gl * gr);
gl := -1073741824; gr := -2; WRITELN(gl * gr);
gl := -1073741824; gr := 3; WRITELN(gl * gr);
gl := -1073741824; gr := 16384; WRITELN(gl * gr);
gl := -1073741824; gr := 32767; WRITELN(gl * gr);
gl := 1073741824; gr := -32768; WRITELN(gl * gr);
gl := 1073741824; gr := -16384; WRITELN(gl * gr);
gl := 1073741824; gr := 2; WRITELN(gl * gr);
gl := 1073741824; gr := 3; WRITELN(gl * gr);
gl := 1073741824; gr := 16384; WRITELN(gl * gr);
gl := 1073741824; gr := 32767; WRITELN(gl * gr);
gl := 2147483647; gr := -32768; WRITELN(gl * gr);
gl := 2147483647; gr := -16384; WRITELN(gl * gr);
gl := 2147483647; gr := -2; WRITELN(gl * gr);
gl := 2147483647; gr := 2; WRITELN(gl * gr);
gl := 2147483647; gr := 3; WRITELN(gl * gr);
gl := 2147483647; gr := 16384; WRITELN(gl * gr);
gl := 2147483647; gr := 32767; WRITELN(gl * gr);
gl := -2147483648; gr := -1; WRITELN(gl DIV gr);
END.
