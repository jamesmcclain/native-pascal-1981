{$MATHCK-}
{ INTEGER op INTEGER8: every sampled combination whose exact result
  overflows INTEGER (same samples and order as mixed_integer_integer8_ok.pas). Under
  MATHCK- each wraps modulo 2^16; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: INTEGER; gr: INTEGER8;
BEGIN
gl := -32768; gr := -128; WRITELN(gl + gr);
gl := -32768; gr := -64; WRITELN(gl + gr);
gl := -32768; gr := -2; WRITELN(gl + gr);
gl := -32768; gr := -1; WRITELN(gl + gr);
gl := 32767; gr := 1; WRITELN(gl + gr);
gl := 32767; gr := 2; WRITELN(gl + gr);
gl := 32767; gr := 3; WRITELN(gl + gr);
gl := 32767; gr := 64; WRITELN(gl + gr);
gl := 32767; gr := 127; WRITELN(gl + gr);
gl := -32768; gr := 1; WRITELN(gl - gr);
gl := -32768; gr := 2; WRITELN(gl - gr);
gl := -32768; gr := 3; WRITELN(gl - gr);
gl := -32768; gr := 64; WRITELN(gl - gr);
gl := -32768; gr := 127; WRITELN(gl - gr);
gl := 32767; gr := -128; WRITELN(gl - gr);
gl := 32767; gr := -64; WRITELN(gl - gr);
gl := 32767; gr := -2; WRITELN(gl - gr);
gl := 32767; gr := -1; WRITELN(gl - gr);
gl := -32768; gr := -128; WRITELN(gl * gr);
gl := -32768; gr := -64; WRITELN(gl * gr);
gl := -32768; gr := -2; WRITELN(gl * gr);
gl := -32768; gr := -1; WRITELN(gl * gr);
gl := -32768; gr := 2; WRITELN(gl * gr);
gl := -32768; gr := 3; WRITELN(gl * gr);
gl := -32768; gr := 64; WRITELN(gl * gr);
gl := -32768; gr := 127; WRITELN(gl * gr);
gl := -16384; gr := -128; WRITELN(gl * gr);
gl := -16384; gr := -64; WRITELN(gl * gr);
gl := -16384; gr := -2; WRITELN(gl * gr);
gl := -16384; gr := 3; WRITELN(gl * gr);
gl := -16384; gr := 64; WRITELN(gl * gr);
gl := -16384; gr := 127; WRITELN(gl * gr);
gl := 16384; gr := -128; WRITELN(gl * gr);
gl := 16384; gr := -64; WRITELN(gl * gr);
gl := 16384; gr := 2; WRITELN(gl * gr);
gl := 16384; gr := 3; WRITELN(gl * gr);
gl := 16384; gr := 64; WRITELN(gl * gr);
gl := 16384; gr := 127; WRITELN(gl * gr);
gl := 32767; gr := -128; WRITELN(gl * gr);
gl := 32767; gr := -64; WRITELN(gl * gr);
gl := 32767; gr := -2; WRITELN(gl * gr);
gl := 32767; gr := 2; WRITELN(gl * gr);
gl := 32767; gr := 3; WRITELN(gl * gr);
gl := 32767; gr := 64; WRITELN(gl * gr);
gl := 32767; gr := 127; WRITELN(gl * gr);
gl := -32768; gr := -1; WRITELN(gl DIV gr);
END.
