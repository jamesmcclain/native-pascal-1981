{ DIALECT: extended }
{ Wide READ skips leading newlines as the vintage INTEGER reader does, and
  leading zeros do not count toward the length of the number. }
PROGRAM ReadWideLines(input, output);
VAR a: INTEGER32; b: INTEGER64; i: INTEGER; f: TEXT;
BEGIN
  READ(a); READ(b); READ(i);
  WRITELN(a); WRITELN(b); WRITELN(i);
  READ(a, b);
  WRITELN(a); WRITELN(b);
  REWRITE(f);
  WRITELN(f, '5');
  WRITELN(f);
  WRITELN(f, '  -000000000000000000000000000000000000000000000000000006');
  RESET(f);
  READ(f, a); READ(f, b);
  WRITELN(a); WRITELN(b);
  CLOSE(f)
END.
