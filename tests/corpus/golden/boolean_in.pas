PROGRAM BooleanIn(OUTPUT);
CONST Yes = TRUE; No = FALSE;
TYPE BoolSet = SET OF BOOLEAN; BoolRange = FALSE..TRUE;
VAR
  empty, falseOnly, trueOnly, full: BoolSet;
  flag, hit: BOOLEAN;
  sub: BoolRange;
  i, leftCalls, rightCalls, tick, leftAt, rightAt: INTEGER;

FUNCTION Echo(b: BOOLEAN): BOOLEAN;
BEGIN
  Echo := b
END;

FUNCTION Left(b: BOOLEAN): BOOLEAN;
BEGIN
  leftCalls := leftCalls + 1;
  tick := tick + 1;
  leftAt := tick;
  Left := b
END;

FUNCTION Right(s: BoolSet): BoolSet;
BEGIN
  rightCalls := rightCalls + 1;
  tick := tick + 1;
  rightAt := tick;
  Right := s
END;

PROCEDURE Count(name: CHAR; result: BOOLEAN);
BEGIN
  WRITELN('count ', name, ' ', result, ' ', leftCalls, ' ', rightCalls);
  leftCalls := 0;
  rightCalls := 0
END;

BEGIN
  leftCalls := 0;
  rightCalls := 0;
  tick := 0;
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
  WRITELN('assign ', hit);
  WRITELN('ctor [] ', FALSE IN [], ' ', TRUE IN []);
  WRITELN('ctor [FALSE] ', FALSE IN [FALSE], ' ', TRUE IN [FALSE]);
  WRITELN('ctor [TRUE] ', FALSE IN [TRUE], ' ', TRUE IN [TRUE]);
  WRITELN('ctor [FALSE..TRUE] ', FALSE IN [FALSE..TRUE], ' ', TRUE IN [FALSE..TRUE]);
  WRITELN('ctor [TRUE..FALSE] ', FALSE IN [TRUE..FALSE], ' ', TRUE IN [TRUE..FALSE]);
  WRITELN('union ', FALSE IN falseOnly + trueOnly, ' ', TRUE IN falseOnly + trueOnly);
  WRITELN('intersection ', FALSE IN full * trueOnly, ' ', TRUE IN full * trueOnly);
  WRITELN('difference ', FALSE IN full - trueOnly, ' ', TRUE IN full - trueOnly);
  hit := Left(TRUE) IN Right(trueOnly);
  Count('h', hit);
  hit := Left(FALSE) IN Right(trueOnly);
  Count('m', hit);
  hit := Left(TRUE) IN Right(empty);
  Count('e', hit);
  hit := Left(FALSE) IN Right(empty) + Right(falseOnly);
  Count('u', hit);
  tick := 0;
  hit := Left(TRUE) IN Right(full);
  WRITELN('order ', leftAt, ' ', rightAt)
END.
