{ DIALECT: extended }
{ The pointer-to-super-array type is carried through a record field. }
PROGRAM SuperRecordFieldPointer(OUTPUT);
TYPE
  Cell = RECORD x, y: INTEGER32 END;
  Cells = SUPER ARRAY [2..*] OF Cell;
  Holder = RECORD data: ^Cells END;
VAR
  h: Holder;
  p: ^Cells;
  j: INTEGER;
BEGIN
  NEW(p, 4);
  h.data := p;
  j := 3;
  h.data^[2].x := 12;
  h.data^[2].y := 13;
  h.data^[j].x := 23;
  h.data^[j].y := 24;
  h.data^[4].x := 34;
  h.data^[4].y := 35;
  WRITELN(h.data^[2].x, ' ', h.data^[2].y);
  WRITELN(h.data^[j].x, ' ', h.data^[j].y);
  WRITELN(h.data^[4].x, ' ', h.data^[4].y);
  DISPOSE(p)
END.
