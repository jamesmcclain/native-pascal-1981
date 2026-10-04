{$MATHCK-}
{ INTEGER8 op INTEGER: every sampled combination whose exact result
  overflows INTEGER (same samples and order as mixed_integer8_integer_ok.pas). Under
  MATHCK- each wraps modulo 2^16; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER8; gr: INTEGER;
BEGIN
gl := -128; gr := -32768; WRITELN(gl + gr);
gl := -64; gr := -32768; WRITELN(gl + gr);
gl := -2; gr := -32768; WRITELN(gl + gr);
gl := -1; gr := -32768; WRITELN(gl + gr);
gl := 1; gr := 32767; WRITELN(gl + gr);
gl := 2; gr := 32767; WRITELN(gl + gr);
gl := 3; gr := 32767; WRITELN(gl + gr);
gl := 64; gr := 32767; WRITELN(gl + gr);
gl := 127; gr := 32767; WRITELN(gl + gr);
gl := -128; gr := 32767; WRITELN(gl - gr);
gl := -64; gr := 32767; WRITELN(gl - gr);
gl := -2; gr := 32767; WRITELN(gl - gr);
gl := 0; gr := -32768; WRITELN(gl - gr);
gl := 1; gr := -32768; WRITELN(gl - gr);
gl := 2; gr := -32768; WRITELN(gl - gr);
gl := 3; gr := -32768; WRITELN(gl - gr);
gl := 64; gr := -32768; WRITELN(gl - gr);
gl := 127; gr := -32768; WRITELN(gl - gr);
gl := -128; gr := -32768; WRITELN(gl * gr);
gl := -128; gr := -16384; WRITELN(gl * gr);
gl := -128; gr := 16384; WRITELN(gl * gr);
gl := -128; gr := 32767; WRITELN(gl * gr);
gl := -64; gr := -32768; WRITELN(gl * gr);
gl := -64; gr := -16384; WRITELN(gl * gr);
gl := -64; gr := 16384; WRITELN(gl * gr);
gl := -64; gr := 32767; WRITELN(gl * gr);
gl := -2; gr := -32768; WRITELN(gl * gr);
gl := -2; gr := -16384; WRITELN(gl * gr);
gl := -2; gr := 32767; WRITELN(gl * gr);
gl := -1; gr := -32768; WRITELN(gl * gr);
gl := 2; gr := -32768; WRITELN(gl * gr);
gl := 2; gr := 16384; WRITELN(gl * gr);
gl := 2; gr := 32767; WRITELN(gl * gr);
gl := 3; gr := -32768; WRITELN(gl * gr);
gl := 3; gr := -16384; WRITELN(gl * gr);
gl := 3; gr := 16384; WRITELN(gl * gr);
gl := 3; gr := 32767; WRITELN(gl * gr);
gl := 64; gr := -32768; WRITELN(gl * gr);
gl := 64; gr := -16384; WRITELN(gl * gr);
gl := 64; gr := 16384; WRITELN(gl * gr);
gl := 64; gr := 32767; WRITELN(gl * gr);
gl := 127; gr := -32768; WRITELN(gl * gr);
gl := 127; gr := -16384; WRITELN(gl * gr);
gl := 127; gr := 16384; WRITELN(gl * gr);
gl := 127; gr := 32767; WRITELN(gl * gr);
END.
