PROGRAM array_named_enum(OUTPUT);
TYPE Color = (red, green, blue);
     Shade = Color;
VAR named: ARRAY [Color] OF INTEGER;
    aliased: ARRAY [Shade] OF INTEGER;
    ranged: ARRAY [red..blue] OF INTEGER;
    c: Color;
BEGIN
  FOR c := red TO blue DO BEGIN
    named[c] := ORD(c) + 10;
    aliased[c] := ORD(c) + 10;
    ranged[c] := ORD(c) + 10
  END;
  WRITELN(named[LOWER(named)], ' ', named[UPPER(named)]);
  WRITELN(aliased[LOWER(aliased)], ' ', aliased[UPPER(aliased)]);
  WRITELN(ranged[LOWER(ranged)], ' ', ranged[UPPER(ranged)]);
  WRITELN(LOWER(named) = LOWER(ranged), ' ',
          UPPER(aliased) = UPPER(ranged))
END.
