PROGRAM indexck_ptr_bad(OUTPUT);
TYPE Row = ARRAY[1..2] OF INTEGER;
     RowPtr = ^Row;
VAR p: RowPtr; i: INTEGER;
BEGIN
  NEW(p);
  p^[1] := 7;
  i := 3;
  WRITELN(p^[i]) { pointer selector before checked load }
END.
