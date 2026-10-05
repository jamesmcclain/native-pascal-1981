{ WORD32 SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(4294967295) = 65535. A WORD-family ABS is its argument. }
PROGRAM BuiltinOk;
VAR a: WORD32;
BEGIN
  a := 4294967294; WRITELN(SUCC(a));  { 4294967295 }
  a := 1; WRITELN(PRED(a));           { 0 }
  a := 0; WRITELN(SUCC(a));           { 1 }
  a := 4294967295; WRITELN(PRED(a));  { 4294967294 }
  a := 0; WRITELN(SUCC(a));           { 1 }
  a := 1; WRITELN(PRED(a));           { 0 }
  a := 4294967295; WRITELN(ABS(a));   { 4294967295 }
  a := 0; WRITELN(ABS(a));            { 0 }
  a := 65535; WRITELN(SQR(a));        { 4294836225 }
  a := 0; WRITELN(SQR(a));            { 0 }
  a := 1; WRITELN(SQR(a));            { 1 }
  a := 2147483648; WRITELN(ABS(a));   { 2147483648 }
  a := 1; WRITELN(ABS(a))             { 1 }
END.
