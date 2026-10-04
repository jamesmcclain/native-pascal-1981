{ INTEGER32 SUCC/PRED/ABS/SQR results that fit: identical under MATHCK+
  and MATHCK- (the suite prepends the directive). Arguments are assigned
  at run time; each comment gives the exact result. SQR tops out at
  isqrt(2147483647) = 46340. }
PROGRAM BuiltinOk;
VAR a: INTEGER32;
BEGIN
  a := 2147483646; WRITELN(SUCC(a));   { 2147483647 }
  a := -2147483647; WRITELN(PRED(a));  { -2147483648 }
  a := -2147483648; WRITELN(SUCC(a));  { -2147483647 }
  a := 2147483647; WRITELN(PRED(a));   { 2147483646 }
  a := 0; WRITELN(SUCC(a));            { 1 }
  a := 1; WRITELN(PRED(a));            { 0 }
  a := 2147483647; WRITELN(ABS(a));    { 2147483647 }
  a := 0; WRITELN(ABS(a));             { 0 }
  a := 46340; WRITELN(SQR(a));         { 2147395600 }
  a := 0; WRITELN(SQR(a));             { 0 }
  a := 1; WRITELN(SQR(a));             { 1 }
  a := -1; WRITELN(SUCC(a));           { 0 }
  a := 0; WRITELN(PRED(a));            { -1 }
  a := -1; WRITELN(PRED(a));           { -2 }
  a := -2147483647; WRITELN(ABS(a));   { 2147483647 }
  a := -1; WRITELN(ABS(a));            { 1 }
  a := -46340; WRITELN(SQR(a));        { 2147395600 }
  a := -1; WRITELN(SQR(a))             { 1 }
END.
