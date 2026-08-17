PROGRAM ReadStdinBasic(input, output);
VAR
  i: INTEGER;
  w: WORD;
  r: REAL;
  c: CHAR;
  s: LSTRING(20);
BEGIN
  READ(i, w);
  READLN;
  READ(r);
  READLN;
  READ(c);
  READLN;
  READLN(s);
  WRITELN(i);
  WRITELN(w);
  WRITELN(r);
  WRITELN(c);
  WRITELN(s);
END.
