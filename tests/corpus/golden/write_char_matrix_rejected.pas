PROGRAM write_char_matrix_rejected(OUTPUT);
{ Only a one-dimensional CHAR array is written as a string. An array of
  CHAR arrays is not a STRING; write its rows (m[1]) instead. }
TYPE Row = ARRAY [1..2] OF CHAR;
VAR m: ARRAY [1..2] OF Row;
BEGIN
  m[1][1] := 'a'; m[1][2] := 'b'; m[2] := m[1];
  WRITELN(m)
END.
