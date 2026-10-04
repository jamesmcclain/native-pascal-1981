{$MATHCK-}
{ WORD32 op WORD8: every sampled combination whose exact result
  overflows WORD32 (same samples and order as mixed_word32_word8_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: WORD32; gr: WORD8;
BEGIN
gl := 4294967295; gr := 1; WRITELN(gl + gr);
gl := 4294967295; gr := 2; WRITELN(gl + gr);
gl := 4294967295; gr := 3; WRITELN(gl + gr);
gl := 4294967295; gr := 128; WRITELN(gl + gr);
gl := 4294967295; gr := 255; WRITELN(gl + gr);
gl := 0; gr := 1; WRITELN(gl - gr);
gl := 0; gr := 2; WRITELN(gl - gr);
gl := 0; gr := 3; WRITELN(gl - gr);
gl := 0; gr := 128; WRITELN(gl - gr);
gl := 0; gr := 255; WRITELN(gl - gr);
gl := 1; gr := 2; WRITELN(gl - gr);
gl := 1; gr := 3; WRITELN(gl - gr);
gl := 1; gr := 128; WRITELN(gl - gr);
gl := 1; gr := 255; WRITELN(gl - gr);
gl := 2; gr := 3; WRITELN(gl - gr);
gl := 2; gr := 128; WRITELN(gl - gr);
gl := 2; gr := 255; WRITELN(gl - gr);
gl := 3; gr := 128; WRITELN(gl - gr);
gl := 3; gr := 255; WRITELN(gl - gr);
gl := 2147483648; gr := 2; WRITELN(gl * gr);
gl := 2147483648; gr := 3; WRITELN(gl * gr);
gl := 2147483648; gr := 128; WRITELN(gl * gr);
gl := 2147483648; gr := 255; WRITELN(gl * gr);
gl := 4294967295; gr := 2; WRITELN(gl * gr);
gl := 4294967295; gr := 3; WRITELN(gl * gr);
gl := 4294967295; gr := 128; WRITELN(gl * gr);
gl := 4294967295; gr := 255; WRITELN(gl * gr);
END.
