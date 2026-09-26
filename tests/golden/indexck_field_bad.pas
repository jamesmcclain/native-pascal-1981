PROGRAM indexck_field_bad(OUTPUT);
TYPE Box = RECORD cells: ARRAY[1..2] OF INTEGER END;
VAR b: Box; i: INTEGER;
BEGIN
  i := 0;
  b.cells[1] := 7;
  b.cells[i] := 9 { field selector before checked store }
END.
