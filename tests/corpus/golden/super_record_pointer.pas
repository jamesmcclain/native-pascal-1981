{ DIALECT: extended }
{ Both ends of the allocated SUPER ARRAY, a variable index, and two fields. }
PROGRAM SuperRecordPointer(OUTPUT);
TYPE
  Cell = RECORD x, y: INTEGER32 END;
  Cells = SUPER ARRAY [0..*] OF Cell;
  CellPtr = ^Cells;
VAR
  p: CellPtr;
  i: INTEGER;
BEGIN
  NEW(p, 3);
  p^[0].x := 11;
  p^[0].y := 12;
  i := 2;
  p^[i].x := 21;
  p^[i].y := 22;
  p^[3].x := 31;
  p^[3].y := 32;
  WRITELN(p^[0].x, ' ', p^[0].y);
  WRITELN(p^[i].x, ' ', p^[i].y);
  WRITELN(p^[3].x, ' ', p^[3].y);
  DISPOSE(p)
END.
