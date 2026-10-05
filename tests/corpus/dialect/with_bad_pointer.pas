PROGRAM WithBadPointer(OUTPUT);
TYPE
  Point = RECORD
    x, y: INTEGER;
  END;
  PPoint = ^Point;
VAR
  pp: PPoint;
BEGIN
  { A bare pointer-to-record WITH target (no explicit ^ deref) must be
    rejected -- the manual and the reference both require an explicit
    dereference. }
  NEW(pp);
  WITH pp DO
    x := 1;
  DISPOSE(pp);
END.
