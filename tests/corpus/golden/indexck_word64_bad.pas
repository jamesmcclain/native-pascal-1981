{ DIALECT: extended }
PROGRAM indexck_word64_bad(OUTPUT);
VAR a: ARRAY[0..1] OF INTEGER; w: WORD64;
BEGIN
  w := MAXWORD64;
  a[w] := 7;
  WRITELN('unreachable')
END.
