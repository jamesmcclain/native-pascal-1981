PROGRAM RecordTest(OUTPUT);
TYPE
  Point = RECORD
    x, y: INTEGER;
  END;
VAR
  pt: Point;
BEGIN
  pt.x := 100;
  pt.y := 200;
  WRITELN('pt = (', pt.x, ', ', pt.y, ')');
END.
