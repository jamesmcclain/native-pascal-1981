{ WORD SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(65535) = 255. A WORD-family ABS is its argument. }
PROGRAM BuiltinOk;
VAR a: WORD;
BEGIN
  a := 65534; WRITELN(SUCC(a));  { 65535 }
  a := 1; WRITELN(PRED(a));      { 0 }
  a := 0; WRITELN(SUCC(a));      { 1 }
  a := 65535; WRITELN(PRED(a));  { 65534 }
  a := 0; WRITELN(SUCC(a));      { 1 }
  a := 1; WRITELN(PRED(a));      { 0 }
  a := 65535; WRITELN(ABS(a));   { 65535 }
  a := 0; WRITELN(ABS(a));       { 0 }
  a := 255; WRITELN(SQR(a));     { 65025 }
  a := 0; WRITELN(SQR(a));       { 0 }
  a := 1; WRITELN(SQR(a));       { 1 }
  a := 32768; WRITELN(ABS(a));   { 32768 }
  a := 1; WRITELN(ABS(a))        { 1 }
END.
