PROGRAM BooleanIn(OUTPUT);
TYPE BoolSet = SET OF BOOLEAN;
VAR
  empty, falseOnly, trueOnly, full: BoolSet;
BEGIN
  empty := [];
  falseOnly := [FALSE];
  trueOnly := [TRUE];
  full := [FALSE, TRUE];
  WRITELN('empty ', FALSE IN empty, ' ', TRUE IN empty);
  WRITELN('false-only ', FALSE IN falseOnly, ' ', TRUE IN falseOnly);
  WRITELN('true-only ', FALSE IN trueOnly, ' ', TRUE IN trueOnly);
  WRITELN('full ', FALSE IN full, ' ', TRUE IN full)
END.
