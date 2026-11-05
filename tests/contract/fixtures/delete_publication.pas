PROGRAM publication;
VAR t, neighbor: LSTRING(5);
PROCEDURE Arm(p, q: ADRMEM) [C]; EXTERN;
PROCEDURE Tick [C]; EXTERN;
FUNCTION count: INTEGER;
BEGIN
  Tick;
  count := 3
END;
BEGIN
  t := 'abcd'; neighbor := 'efgh';
  Arm(ADR t, ADR neighbor);
  {$RANGECK-}
  DELETE(t, 3, count);
  WRITELN('wrong')
END.
