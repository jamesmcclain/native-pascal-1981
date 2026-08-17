PROGRAM WholeStringOps(output);
TYPE
  Name = LSTRING(16);
VAR
  names: ARRAY [1..3] OF Name;
  a, b, c, tmp: Name;
BEGIN
  names[1] := 'alpha';
  names[2] := 'beta';
  names[3] := 'alpha';

  a := 'alpha';
  b := names[1];
  c := names[2];

  IF a = b THEN
    WRITELN('a equals b')
  ELSE
    WRITELN('a differs from b');

  IF a = c THEN
    WRITELN('a equals c')
  ELSE
    WRITELN('a differs from c');

  tmp := names[1]; WRITELN(tmp);
  tmp := names[2]; WRITELN(tmp);
  tmp := names[3]; WRITELN(tmp);
END.
