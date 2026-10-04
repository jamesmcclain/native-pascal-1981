{$MATHCK+}
PROGRAM Named;
VAR a: INTEGER32; i: INTEGER;
BEGIN
  a := 100000; i := 20000; WRITELN(a * i); WRITELN(i * a);
  a := 2147483647; i := 1; WRITELN(a - i + i)
END.
