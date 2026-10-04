{$MATHCK-}
{ WORD op WORD8: every sampled combination whose exact result
  overflows WORD (same samples and order as mixed_word_word8_ok.pas). Under
  MATHCK- each wraps modulo 2^16; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: WORD; gr: WORD8;
BEGIN
gl := 65535; gr := 1; WRITELN(gl + gr);
gl := 65535; gr := 2; WRITELN(gl + gr);
gl := 65535; gr := 3; WRITELN(gl + gr);
gl := 65535; gr := 128; WRITELN(gl + gr);
gl := 65535; gr := 255; WRITELN(gl + gr);
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
gl := 32768; gr := 2; WRITELN(gl * gr);
gl := 32768; gr := 3; WRITELN(gl * gr);
gl := 32768; gr := 128; WRITELN(gl * gr);
gl := 32768; gr := 255; WRITELN(gl * gr);
gl := 65535; gr := 2; WRITELN(gl * gr);
gl := 65535; gr := 3; WRITELN(gl * gr);
gl := 65535; gr := 128; WRITELN(gl * gr);
gl := 65535; gr := 255; WRITELN(gl * gr);
END.
