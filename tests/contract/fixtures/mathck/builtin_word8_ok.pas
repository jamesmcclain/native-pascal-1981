{ WORD8 SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(255) = 15. A WORD-family ABS is its argument. }
PROGRAM BuiltinOk;
VAR a: WORD8;
BEGIN
  a := 254; WRITELN(SUCC(a));  { 255 }
  a := 1; WRITELN(PRED(a));    { 0 }
  a := 0; WRITELN(SUCC(a));    { 1 }
  a := 255; WRITELN(PRED(a));  { 254 }
  a := 0; WRITELN(SUCC(a));    { 1 }
  a := 1; WRITELN(PRED(a));    { 0 }
  a := 255; WRITELN(ABS(a));   { 255 }
  a := 0; WRITELN(ABS(a));     { 0 }
  a := 15; WRITELN(SQR(a));    { 225 }
  a := 0; WRITELN(SQR(a));     { 0 }
  a := 1; WRITELN(SQR(a));     { 1 }
  a := 128; WRITELN(ABS(a));   { 128 }
  a := 1; WRITELN(ABS(a))      { 1 }
END.
