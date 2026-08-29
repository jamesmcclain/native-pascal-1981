{ A CHAR-keyed CASE. Legal in the vintage dialect and used by real period
  programs to dispatch on an input character, so it is exercised here rather
  than under tests/dialect. Covers multiple constants per arm, OTHERWISE, and
  a CASE nested inside a loop. }
PROGRAM CaseChar(OUTPUT);
VAR
  s: LSTRING(12);
  i, vowels, digits, other: INTEGER;
  c: CHAR;
BEGIN
  s := 'Pascal 1981!';
  vowels := 0;
  digits := 0;
  other := 0;
  FOR i := 1 TO ORD(s.LEN) DO
  BEGIN
    c := s[i];
    CASE c OF
      'a', 'e', 'i', 'o', 'u': vowels := vowels + 1;
      '0', '1', '8', '9': digits := digits + 1;
      OTHERWISE other := other + 1
    END;
  END;
  WRITELN('vowels: ', vowels);
  WRITELN('digits: ', digits);
  WRITELN('other: ', other);

  c := 'b';
  CASE c OF
    'a': WRITELN('no otherwise: a');
    'b': WRITELN('no otherwise: b')
  END;
END.
