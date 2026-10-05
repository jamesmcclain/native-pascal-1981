{$MATHCK-}
{ WORD8 op WORD32: every sampled combination whose exact result
  overflows WORD32 (same samples and order as mixed_word8_word32_ok.pas). Under
  MATHCK- each wraps modulo 2^32; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: WORD8; gr: WORD32;
BEGIN
gl := 1; gr := 4294967295; WRITELN(gl + gr);
gl := 2; gr := 4294967295; WRITELN(gl + gr);
gl := 3; gr := 4294967295; WRITELN(gl + gr);
gl := 128; gr := 4294967295; WRITELN(gl + gr);
gl := 255; gr := 4294967295; WRITELN(gl + gr);
gl := 0; gr := 1; WRITELN(gl - gr);
gl := 0; gr := 2; WRITELN(gl - gr);
gl := 0; gr := 3; WRITELN(gl - gr);
gl := 0; gr := 2147483648; WRITELN(gl - gr);
gl := 0; gr := 4294967295; WRITELN(gl - gr);
gl := 1; gr := 2; WRITELN(gl - gr);
gl := 1; gr := 3; WRITELN(gl - gr);
gl := 1; gr := 2147483648; WRITELN(gl - gr);
gl := 1; gr := 4294967295; WRITELN(gl - gr);
gl := 2; gr := 3; WRITELN(gl - gr);
gl := 2; gr := 2147483648; WRITELN(gl - gr);
gl := 2; gr := 4294967295; WRITELN(gl - gr);
gl := 3; gr := 2147483648; WRITELN(gl - gr);
gl := 3; gr := 4294967295; WRITELN(gl - gr);
gl := 128; gr := 2147483648; WRITELN(gl - gr);
gl := 128; gr := 4294967295; WRITELN(gl - gr);
gl := 255; gr := 2147483648; WRITELN(gl - gr);
gl := 255; gr := 4294967295; WRITELN(gl - gr);
gl := 2; gr := 2147483648; WRITELN(gl * gr);
gl := 2; gr := 4294967295; WRITELN(gl * gr);
gl := 3; gr := 2147483648; WRITELN(gl * gr);
gl := 3; gr := 4294967295; WRITELN(gl * gr);
gl := 128; gr := 2147483648; WRITELN(gl * gr);
gl := 128; gr := 4294967295; WRITELN(gl * gr);
gl := 255; gr := 2147483648; WRITELN(gl * gr);
gl := 255; gr := 4294967295; WRITELN(gl * gr);
END.
