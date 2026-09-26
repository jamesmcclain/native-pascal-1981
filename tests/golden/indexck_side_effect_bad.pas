PROGRAM indexck_side_effect_bad(OUTPUT);
VAR a: ARRAY[1..2] OF INTEGER; calls: INTEGER;
FUNCTION Bump: INTEGER;
BEGIN
  calls := calls + 1;
  WRITELN(calls);
  Bump := 0
END;
BEGIN
  calls := 0;
  a[Bump] := 9 { stdout flushed before diagnostic; Bump called once }
END.
