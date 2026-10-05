PROGRAM array_named_boolean(OUTPUT);
VAR named: ARRAY [BOOLEAN] OF INTEGER;
    ranged: ARRAY [FALSE..TRUE] OF INTEGER;
BEGIN
  named[FALSE] := 12; named[TRUE] := 34;
  ranged[FALSE] := 12; ranged[TRUE] := 34;
  WRITELN(named[LOWER(named)], ' ', named[UPPER(named)]);
  WRITELN(ranged[LOWER(ranged)], ' ', ranged[UPPER(ranged)]);
  WRITELN(LOWER(named) = LOWER(ranged), ' ',
          UPPER(named) = UPPER(ranged))
END.
