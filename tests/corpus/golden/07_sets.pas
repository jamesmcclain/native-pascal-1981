PROGRAM SetTest(OUTPUT);
TYPE
  NumSet = SET OF 1..10;
VAR
  s: NumSet;
BEGIN
  s := [1, 3, 5, 7, 9];
  IF 3 IN s THEN
    WRITELN('3 is in set');
  IF NOT (4 IN s) THEN
    WRITELN('4 is not in set');
END.
