PROGRAM indexck_nested_bad(OUTPUT);
TYPE Row = ARRAY[1..2] OF INTEGER;
     Grid = ARRAY[1..2] OF Row;
VAR g: Grid; i, j: INTEGER;
BEGIN
  i := 1; j := 0;
  g[1][1] := 7;
  WRITELN(g[i,j]) { inner dimension below range }
END.
