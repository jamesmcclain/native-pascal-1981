PROGRAM array_named_subrange(OUTPUT);
CONST Last = 4;
TYPE Index = 2..Last;
     Slot = Index;
VAR named: ARRAY [Index] OF INTEGER;
    aliased: ARRAY [Slot] OF INTEGER;
    ranged: ARRAY [2..Last] OF INTEGER;
    real_named: ARRAY [Index] OF REAL;
    real_ranged: ARRAY [2..Last] OF REAL;
    i: Index;
BEGIN
  FOR i := 2 TO Last DO BEGIN
    named[i] := i * 10;
    aliased[i] := i * 10;
    ranged[i] := i * 10;
    real_named[i] := i;
    real_ranged[i] := i
  END;
  WRITELN(named[LOWER(named)], ' ', named[UPPER(named)]);
  WRITELN(aliased[LOWER(aliased)], ' ', aliased[UPPER(aliased)]);
  WRITELN(ranged[LOWER(ranged)], ' ', ranged[UPPER(ranged)]);
  WRITELN(LOWER(named), ' ', UPPER(named), ' ',
          LOWER(ranged), ' ', UPPER(ranged));
  WRITELN(real_named[LOWER(real_named)] = real_ranged[LOWER(real_ranged)],
          ' ', real_named[UPPER(real_named)] = real_ranged[UPPER(real_ranged)])
END.
