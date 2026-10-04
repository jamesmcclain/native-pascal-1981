PROGRAM WithStmtTest(OUTPUT);
TYPE
  Point = RECORD
    x, y: INTEGER;
  END;
  PPoint = ^Point;
VAR
  p1, p2: Point;
  pp: PPoint;
BEGIN
  { single-target WITH: field reads/writes affect the record in place }
  WITH p1 DO
  BEGIN
    x := 10;
    y := 20;
  END;
  WRITELN('p1 = (', p1.x, ', ', p1.y, ')');

  { multi-target WITH: WITH p1, p2 DO body === WITH p1 DO WITH p2 DO body,
    so a field name common to both resolves against the last-listed
    target }
  p1.x := 1;
  p2.x := 2;
  WITH p1, p2 DO
    WRITELN('shadowed x = ', x);

  { nested WITH }
  p1.x := 100;
  p1.y := 200;
  WITH p1 DO
  BEGIN
    WITH p1 DO
      WRITELN('nested x = ', x);
    y := y + 1;
  END;
  WRITELN('p1.y after nested = ', p1.y);

  { WITH on a dereferenced pointer to record }
  NEW(pp);
  pp^.x := 7;
  pp^.y := 8;
  WITH pp^ DO
    WRITELN('pp^ = (', x, ', ', y, ')');
  DISPOSE(pp);
END.
