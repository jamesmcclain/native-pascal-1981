{$MATHCK-}
{ INTEGER op INTEGER32: every sampled combination whose exact result
  overflows INTEGER32 (same samples and order as mixed_integer_integer32_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER; gr: INTEGER32;
BEGIN
gl := -32768; gr := -2147483648; WRITELN(gl + gr);
gl := -16384; gr := -2147483648; WRITELN(gl + gr);
gl := -2; gr := -2147483648; WRITELN(gl + gr);
gl := -1; gr := -2147483648; WRITELN(gl + gr);
gl := 1; gr := 2147483647; WRITELN(gl + gr);
gl := 2; gr := 2147483647; WRITELN(gl + gr);
gl := 3; gr := 2147483647; WRITELN(gl + gr);
gl := 16384; gr := 2147483647; WRITELN(gl + gr);
gl := 32767; gr := 2147483647; WRITELN(gl + gr);
gl := -32768; gr := 2147483647; WRITELN(gl - gr);
gl := -16384; gr := 2147483647; WRITELN(gl - gr);
gl := -2; gr := 2147483647; WRITELN(gl - gr);
gl := 0; gr := -2147483648; WRITELN(gl - gr);
gl := 1; gr := -2147483648; WRITELN(gl - gr);
gl := 2; gr := -2147483648; WRITELN(gl - gr);
gl := 3; gr := -2147483648; WRITELN(gl - gr);
gl := 16384; gr := -2147483648; WRITELN(gl - gr);
gl := 32767; gr := -2147483648; WRITELN(gl - gr);
gl := -32768; gr := -2147483648; WRITELN(gl * gr);
gl := -32768; gr := -1073741824; WRITELN(gl * gr);
gl := -32768; gr := 1073741824; WRITELN(gl * gr);
gl := -32768; gr := 2147483647; WRITELN(gl * gr);
gl := -16384; gr := -2147483648; WRITELN(gl * gr);
gl := -16384; gr := -1073741824; WRITELN(gl * gr);
gl := -16384; gr := 1073741824; WRITELN(gl * gr);
gl := -16384; gr := 2147483647; WRITELN(gl * gr);
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
gl := 16384; gr := -2147483648; WRITELN(gl * gr);
gl := 16384; gr := -1073741824; WRITELN(gl * gr);
gl := 16384; gr := 1073741824; WRITELN(gl * gr);
gl := 16384; gr := 2147483647; WRITELN(gl * gr);
gl := 32767; gr := -2147483648; WRITELN(gl * gr);
gl := 32767; gr := -1073741824; WRITELN(gl * gr);
gl := 32767; gr := 1073741824; WRITELN(gl * gr);
gl := 32767; gr := 2147483647; WRITELN(gl * gr);
END.
