{$MATHCK-}
{ WORD32 op WORD64: every sampled combination whose exact result
  overflows WORD64 (same samples and order as mixed_word32_word64_ok.pas). Under
  MATHCK- each wraps modulo 2^64; .out holds the wrapped values.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidth;
VAR gl: WORD32; gr: WORD64;
BEGIN
gl := 1; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 2; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 3; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 2147483648; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 4294967295; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl + gr);
gl := 0; gr := 1; WRITELN(gl - gr);
gl := 0; gr := 2; WRITELN(gl - gr);
gl := 0; gr := 3; WRITELN(gl - gr);
gl := 0; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 0; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 1; gr := 2; WRITELN(gl - gr);
gl := 1; gr := 3; WRITELN(gl - gr);
gl := 1; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 1; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 2; gr := 3; WRITELN(gl - gr);
gl := 2; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 2; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 3; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 3; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 2147483648; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 2147483648; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 4294967295; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl - gr);
gl := 4294967295; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl - gr);
gl := 2; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 3; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 3; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 2147483648; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 2147483648; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
gl := 4294967295; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0; WRITELN(gl * gr);
gl := 4294967295; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295; WRITELN(gl * gr);
END.
