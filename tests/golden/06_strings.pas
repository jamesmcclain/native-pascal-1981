PROGRAM StringTest(OUTPUT);
VAR
  s1, s2: LSTRING(32);
BEGIN
  s1 := 'Pascal';
  s2 := ' 1981';
  CONCAT(s1, s2);
  WRITELN('concatenated: ', s1);
END.
