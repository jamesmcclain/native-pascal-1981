{ INTEGER8 SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(127) = 11. }
PROGRAM BuiltinOk;
VAR a: INTEGER8;
BEGIN
  a := 126; WRITELN(SUCC(a));   { 127 }
  a := -127; WRITELN(PRED(a));  { -128 }
  a := -128; WRITELN(SUCC(a));  { -127 }
  a := 127; WRITELN(PRED(a));   { 126 }
  a := 0; WRITELN(SUCC(a));     { 1 }
  a := 1; WRITELN(PRED(a));     { 0 }
  a := 127; WRITELN(ABS(a));    { 127 }
  a := 0; WRITELN(ABS(a));      { 0 }
  a := 11; WRITELN(SQR(a));     { 121 }
  a := 0; WRITELN(SQR(a));      { 0 }
  a := 1; WRITELN(SQR(a));      { 1 }
  a := -1; WRITELN(SUCC(a));    { 0 }
  a := 0; WRITELN(PRED(a));     { -1 }
  a := -1; WRITELN(PRED(a));    { -2 }
  a := -127; WRITELN(ABS(a));   { 127 }
  a := -1; WRITELN(ABS(a));     { 1 }
  a := -11; WRITELN(SQR(a));    { 121 }
  a := -1; WRITELN(SQR(a))      { 1 }
END.
