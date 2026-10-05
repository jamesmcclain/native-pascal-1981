PROGRAM array_named_char(OUTPUT);
TYPE Letters = 'm'..'o';
VAR named: ARRAY [Letters] OF INTEGER;
    ranged: ARRAY ['m'..'o'] OF INTEGER;
    c: Letters;
BEGIN
  FOR c := 'm' TO 'o' DO BEGIN
    named[c] := ORD(c);
    ranged[c] := ORD(c)
  END;
  WRITELN(named[LOWER(named)], ' ', named[UPPER(named)]);
  WRITELN(ranged[LOWER(ranged)], ' ', ranged[UPPER(ranged)]);
  WRITELN(LOWER(named), UPPER(named), ' ',
          LOWER(ranged), UPPER(ranged))
END.
