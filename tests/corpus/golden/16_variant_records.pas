PROGRAM VariantRecords;
TYPE
  Tagged = RECORD
    fixed: INTEGER;
    CASE kind: INTEGER OF
      1: (letter: CHAR);
      2: (number: REAL)
  END;
  Tagless = RECORD
    CASE BOOLEAN OF
      TRUE: (yes: INTEGER);
      FALSE: (no: CHAR)
  END;
VAR
  r: Tagged;
  t: Tagless;
BEGIN
  r.fixed := 7;
  r.kind := 1;
  r.letter := 'x';
  WITH r DO
    WRITELN(fixed, ' ', kind, ' ', letter);
  t.yes := 42;
  WRITELN(t.yes)
END.
