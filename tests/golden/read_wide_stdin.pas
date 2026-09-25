{ DIALECT: extended }
PROGRAM ReadWideStdin(input, output);
VAR a: INTEGER32; b: INTEGER64;
BEGIN
  READ(a, b);
  WRITELN(a); WRITELN(b);
  READLN(a, b);
  WRITELN(a); WRITELN(b);
  READLN(a, b);
  WRITELN(a); WRITELN(b);
  READLN(a, b);
  WRITELN(a); WRITELN(b)
END.
