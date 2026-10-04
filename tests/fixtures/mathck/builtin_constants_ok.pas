PROGRAM Folded;
CONST M = 32767; N = -32768;
VAR i: INTEGER; j: INTEGER32;
BEGIN
  i := SUCC(M - 1); WRITELN(i, ' ', PRED(N + 1), ' ', SUCC(SUCC(3)));
  j := SUCC(M); WRITELN(j); j := PRED(N); WRITELN(j);
  i := ABS(N + 1); WRITELN(i, ' ', SQR(-181), ' ', ABS(-5));
  j := ABS(N); WRITELN(j); j := SQR(200); WRITELN(j);
END.
