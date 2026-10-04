PROGRAM SetOpsTest(OUTPUT);
TYPE
  NumSet = SET OF 1..10;
  CharSet = SET OF CHAR;
VAR
  a, b, u, i, d: NumSet;
  vowels: CharSet;
BEGIN
  a := [1, 2, 3, 4];
  b := [3, 4, 5, 6];

  u := a + b;
  IF (1 IN u) AND (5 IN u) AND (3 IN u) THEN
    WRITELN('union ok');

  i := a * b;
  IF (3 IN i) AND (4 IN i) AND NOT (1 IN i) AND NOT (5 IN i) THEN
    WRITELN('intersection ok');

  d := a - b;
  IF (1 IN d) AND (2 IN d) AND NOT (3 IN d) AND NOT (5 IN d) THEN
    WRITELN('difference ok');

  IF a = a THEN
    WRITELN('eq ok');
  IF a <> b THEN
    WRITELN('neq ok');
  IF [1, 2] <= a THEN
    WRITELN('le ok');
  IF a >= [1, 2] THEN
    WRITELN('ge ok');
  IF [1, 2] < a THEN
    WRITELN('lt ok');
  IF a > [1, 2] THEN
    WRITELN('gt ok');

  vowels := ['a', 'e', 'i', 'o', 'u'];
  IF ('e' IN vowels) AND NOT ('b' IN vowels) THEN
    WRITELN('char set ok');
END.
