PROGRAM ArrayTest(OUTPUT);
VAR
  arr: ARRAY [1..4] OF INTEGER;
  i: INTEGER;
BEGIN
  FOR i := 1 TO 4 DO
    arr[i] := i * 10;
  FOR i := 1 TO 4 DO
    WRITELN('arr[', i, '] = ', arr[i]);
END.
