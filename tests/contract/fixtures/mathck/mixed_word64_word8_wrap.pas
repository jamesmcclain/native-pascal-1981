{$MATHCK-}
{ WORD64 op WORD8: every sampled combination whose exact result
  overflows WORD64 (same samples and order as mixed_word64_word8_ok.pas). Under
  MATHCK- each wraps modulo 2^64; .out holds the wrapped values.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidth;
VAR gl: WORD64; gr: WORD8;
BEGIN
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1; WRITELN(gl + gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2; WRITELN(gl + gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 3; WRITELN(gl + gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 128; WRITELN(gl + gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 255; WRITELN(gl + gr);
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
gl := 2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2; WRITELN(gl * gr);
gl := 2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 3; WRITELN(gl * gr);
gl := 2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 128; WRITELN(gl * gr);
gl := 2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 255; WRITELN(gl * gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2; WRITELN(gl * gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 3; WRITELN(gl * gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 128; WRITELN(gl * gr);
gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 255; WRITELN(gl * gr);
END.
