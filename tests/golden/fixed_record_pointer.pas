{ DIALECT: extended }
{ A fixed array of records behind a pointer, reached directly and through
  a record field. The field holds a different allocation. }
PROGRAM FixedRecordPointer(OUTPUT);
TYPE
  Cell = RECORD x, y: INTEGER32 END;
  Cells = ARRAY [1..3] OF Cell;
  CellPtr = ^Cells;
  Holder = RECORD data: CellPtr END;
VAR
  p, q: CellPtr;
  h: Holder;
  i: INTEGER;
BEGIN
  NEW(p);
  NEW(q);
  h.data := q;
  i := 3;
  p^[1].x := 101;
  p^[1].y := 102;
  p^[i].x := 103;
  p^[i].y := 104;
  h.data^[1].x := 201;
  h.data^[1].y := 202;
  h.data^[i].x := 203;
  h.data^[i].y := 204;
  WRITELN(p^[1].x, ' ', p^[1].y, ' ', p^[i].x, ' ', p^[i].y);
  WRITELN(h.data^[1].x, ' ', h.data^[1].y, ' ', h.data^[i].x, ' ', h.data^[i].y);
  DISPOSE(q);
  DISPOSE(p)
END.
