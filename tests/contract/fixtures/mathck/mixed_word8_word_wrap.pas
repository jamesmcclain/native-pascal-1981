{$MATHCK-}
{ WORD8 op WORD: every sampled combination whose exact result
  overflows WORD (same samples and order as mixed_word8_word_ok.pas). Under
  MATHCK- each wraps modulo 2^16; .out holds the wrapped values. }
PROGRAM MixedWidth;
VAR gl: WORD8; gr: WORD;
BEGIN
gl := 1; gr := 65535; WRITELN(gl + gr);
gl := 2; gr := 65535; WRITELN(gl + gr);
gl := 3; gr := 65535; WRITELN(gl + gr);
gl := 128; gr := 65535; WRITELN(gl + gr);
gl := 255; gr := 65535; WRITELN(gl + gr);
gl := 0; gr := 1; WRITELN(gl - gr);
gl := 0; gr := 2; WRITELN(gl - gr);
gl := 0; gr := 3; WRITELN(gl - gr);
gl := 0; gr := 32768; WRITELN(gl - gr);
gl := 0; gr := 65535; WRITELN(gl - gr);
gl := 1; gr := 2; WRITELN(gl - gr);
gl := 1; gr := 3; WRITELN(gl - gr);
gl := 1; gr := 32768; WRITELN(gl - gr);
gl := 1; gr := 65535; WRITELN(gl - gr);
gl := 2; gr := 3; WRITELN(gl - gr);
gl := 2; gr := 32768; WRITELN(gl - gr);
gl := 2; gr := 65535; WRITELN(gl - gr);
gl := 3; gr := 32768; WRITELN(gl - gr);
gl := 3; gr := 65535; WRITELN(gl - gr);
gl := 128; gr := 32768; WRITELN(gl - gr);
gl := 128; gr := 65535; WRITELN(gl - gr);
gl := 255; gr := 32768; WRITELN(gl - gr);
gl := 255; gr := 65535; WRITELN(gl - gr);
gl := 2; gr := 32768; WRITELN(gl * gr);
gl := 2; gr := 65535; WRITELN(gl * gr);
gl := 3; gr := 32768; WRITELN(gl * gr);
gl := 3; gr := 65535; WRITELN(gl * gr);
gl := 128; gr := 32768; WRITELN(gl * gr);
gl := 128; gr := 65535; WRITELN(gl * gr);
gl := 255; gr := 32768; WRITELN(gl * gr);
gl := 255; gr := 65535; WRITELN(gl * gr);
END.
