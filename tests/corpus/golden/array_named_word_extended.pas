PROGRAM array_named_word(OUTPUT);
VAR
  named: ARRAY [WORD] OF INTEGER;
  ranged: ARRAY [0..65535] OF INTEGER;
  w: WORD;
BEGIN
  named[0] := 10;
  named[65535] := 12;
  ranged[0] := 10;
  ranged[65535] := 12;
  w := LOWER(named);
  WRITE(w, ' ', UPPER(named));
  WRITELN;
  WRITE(named[0], ' ', named[65535], ' ', ranged[0], ' ', ranged[65535]);
  WRITELN
END.
