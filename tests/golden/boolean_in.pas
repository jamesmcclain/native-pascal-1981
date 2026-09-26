PROGRAM BooleanIn(OUTPUT);
CONST Yes = TRUE; No = FALSE;
TYPE BoolSet = SET OF BOOLEAN; BoolRange = FALSE..TRUE;
VAR
  empty, falseOnly, trueOnly, full: BoolSet;
  flag, hit: BOOLEAN;
  sub: BoolRange;
  i: INTEGER;

FUNCTION Echo(b: BOOLEAN): BOOLEAN;
BEGIN
  Echo := b
END;

BEGIN
  empty := [];
  falseOnly := [FALSE];
  trueOnly := [TRUE];
  full := [FALSE, TRUE];
  WRITELN('empty ', FALSE IN empty, ' ', TRUE IN empty);
  WRITELN('false-only ', FALSE IN falseOnly, ' ', TRUE IN falseOnly);
  WRITELN('true-only ', FALSE IN trueOnly, ' ', TRUE IN trueOnly);
  WRITELN('full ', FALSE IN full, ' ', TRUE IN full);
  flag := TRUE;
  WRITELN('variable ', flag IN trueOnly, ' ', flag IN falseOnly);
  WRITELN('not ', (NOT flag) IN falseOnly, ' ', (NOT flag) IN trueOnly);
  WRITELN('constant ', Yes IN trueOnly, ' ', No IN trueOnly);
  i := 3;
  WRITELN('comparison ', (i > 2) IN trueOnly, ' ', (i < 2) IN trueOnly);
  WRITELN('function ', Echo(FALSE) IN falseOnly, ' ', Echo(TRUE) IN falseOnly);
  sub := TRUE;
  WRITELN('subrange ', sub IN trueOnly, ' ', sub IN falseOnly);
  IF flag IN trueOnly THEN WRITELN('if hit') ELSE WRITELN('if miss');
  IF flag IN falseOnly THEN WRITELN('if hit') ELSE WRITELN('if miss');
  hit := flag IN full;
  WRITELN('assign ', hit);
  hit := flag IN empty;
  WRITELN('assign ', hit)
END.
