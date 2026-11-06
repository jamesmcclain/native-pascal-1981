{ DIALECT: vintage extended }
PROGRAM sizeof_word_actual(OUTPUT);
{ SIZEOF is a WORD (IBM manual), so it is an admissible actual for a WORD
  value formal and for a WORD variable. It stays admissible for an INTEGER
  variable and INTEGER formal as well. }
VAR
  a: ARRAY [1..4] OF INTEGER;
  i: INTEGER;
  w: WORD;
PROCEDURE p(len: WORD);
BEGIN
  WRITELN(len)
END;
PROCEDURE q(n: INTEGER);
BEGIN
  WRITELN(n)
END;
BEGIN
  p(SIZEOF(a));
  w := SIZEOF(a);
  WRITELN(w);
  i := SIZEOF(a);
  WRITELN(i);
  q(SIZEOF(a));
  IF i = SIZEOF(a) THEN WRITELN('equal')
END.
