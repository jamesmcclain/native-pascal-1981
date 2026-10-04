{ INTEGER SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(32767) = 181. }
PROGRAM BuiltinOk;
VAR a: INTEGER;
BEGIN
  a := 32766; WRITELN(SUCC(a));   { 32767 }
  a := -32767; WRITELN(PRED(a));  { -32768 }
  a := -32768; WRITELN(SUCC(a));  { -32767 }
  a := 32767; WRITELN(PRED(a));   { 32766 }
  a := 0; WRITELN(SUCC(a));       { 1 }
  a := 1; WRITELN(PRED(a));       { 0 }
  a := 32767; WRITELN(ABS(a));    { 32767 }
  a := 0; WRITELN(ABS(a));        { 0 }
  a := 181; WRITELN(SQR(a));      { 32761 }
  a := 0; WRITELN(SQR(a));        { 0 }
  a := 1; WRITELN(SQR(a));        { 1 }
  a := -1; WRITELN(SUCC(a));      { 0 }
  a := 0; WRITELN(PRED(a));       { -1 }
  a := -1; WRITELN(PRED(a));      { -2 }
  a := -32767; WRITELN(ABS(a));   { 32767 }
  a := -1; WRITELN(ABS(a));       { 1 }
  a := -181; WRITELN(SQR(a));     { 32761 }
  a := -1; WRITELN(SQR(a))        { 1 }
END.
