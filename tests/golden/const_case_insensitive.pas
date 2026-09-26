PROGRAM const_case_insensitive(OUTPUT);
{ A CONST name is case-insensitive in every position: a value, an array
  bound, and an enumeration member. Regression guard: codegen matched
  CONST names exactly, so BIG was an undefined variable. }
TYPE
  Color = (Red, Green);
CONST
  Big = 7;
VAR
  a: ARRAY [1..BIG] OF INTEGER;
  c: Color;
BEGIN
  a[big] := 3;
  WRITELN(BIG, ' ', big, ' ', a[7]);
  c := GREEN;
  IF c = green THEN WRITELN('green')
END.
