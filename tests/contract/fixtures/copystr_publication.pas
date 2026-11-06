PROGRAM publication;
VAR t, neighbor: STRING(3);
PROCEDURE Arm(p, q: ADRMEM) [C]; EXTERN;
PROCEDURE Tick [C]; EXTERN;
FUNCTION source: LSTRING(4);
BEGIN
  Tick;
  source := 'wxyz'
END;
BEGIN
  t := 'abc'; neighbor := 'def';
  Arm(ADR t, ADR neighbor);
  {$RANGECK-}
  COPYSTR(source, t);
  WRITELN('wrong')
END.
