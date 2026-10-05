PROGRAM indexck_fixed_guard(OUTPUT);
TYPE Row = ARRAY[2..3] OF INTEGER;
     Grid = ARRAY[4..5] OF Row;
     Box = RECORD cells: Grid END;
     BoxPtr = ^Box;
VAR b: Box; p: BoxPtr; i, j, calls: INTEGER;
FUNCTION Next: INTEGER;
BEGIN
  calls := calls + 1;
  Next := 4
END;
BEGIN
  NEW(p);
  i := 5; j := 3;
  b.cells[4][2] := 11;
  p^.cells[i,j] := 29;
  WRITELN(b.cells[4][2], ' ', p^.cells[5][3]);
  p^.cells[Next,2] := 17;
  WRITELN(p^.cells[4,2], ' ', calls);
  {$INDEXCK-} b.cells[4][3] := 7;
  {$INDEXCK+} WRITELN(b.cells[4][3]);
  DISPOSE(p)
END.
