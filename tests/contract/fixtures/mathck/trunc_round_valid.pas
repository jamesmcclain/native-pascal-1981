PROGRAM Conversion(output);
VAR r, z: REAL; i: INTEGER;
BEGIN
  r := 0.0; z := 0.0;
  i := TRUNC(r + 32767.9); WRITELN(i);
  i := TRUNC(r - 32768.9); WRITELN(i);
  i := TRUNC(r - 0.5); WRITELN(i);
  i := TRUNC(r + 7.99); WRITELN(i);
  i := ROUND(r + 32767.4); WRITELN(i);
  i := ROUND(r - 32768.4); WRITELN(i);
  i := ROUND(r + 2.5); WRITELN(i);
  i := ROUND(r - 2.5); WRITELN(i);
  i := ROUND(r + 0.4); WRITELN(i);
  i := ROUND(r - 0.5); WRITELN(i);
END.
