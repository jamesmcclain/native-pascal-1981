PROGRAM publication;
VAR t, neighbor: LSTRING(5);
PROCEDURE Arm(p, q: ADRMEM) [C]; EXTERN;
PROCEDURE Tick [C]; EXTERN;
FUNCTION source: LSTRING(4);
BEGIN
  Tick;
  source := 'wxyz'
END;
BEGIN
  t := 'abc'; neighbor := 'efgh';
  Arm(ADR t, ADR neighbor);
  {$RANGECK-}
  INSERT(source, t, 2);
  WRITELN('wrong')
END.
