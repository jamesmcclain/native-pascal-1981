{ UPPER and LOWER of an array element that is itself an array, and of an
  array field named inside WITH, have the inner array's index type. }
PROGRAM BoundNestedElement(OUTPUT);
TYPE
  Row = ARRAY['a'..'c'] OF INTEGER;
  Rec = RECORD cells: ARRAY['p'..'t'] OF INTEGER END;
VAR
  m: ARRAY[1..3] OF Row;
  r: Rec;
  c: CHAR;
  i: INTEGER;
BEGIN
  c := UPPER(m[1]);
  WRITELN(c, LOWER(m[2]));
  i := UPPER(m);
  WRITELN(i);
  WITH r DO c := UPPER(cells);
  WRITELN(c, LOWER(r.cells))
END.
