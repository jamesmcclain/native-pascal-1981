PROGRAM publication;
VAR t, neighbor: LSTRING(3);
PROCEDURE Arm(p, q: ADRMEM) [C]; EXTERN;
PROCEDURE Tick [C]; EXTERN;
FUNCTION source: LSTRING(4);
BEGIN
  Tick;
  source := 'wxyz'
END;
BEGIN
  t := 'abc'; neighbor := 'def';
  t := 'ab';
  Arm(ADR t, ADR neighbor);
  {$RANGECK+}
  COPYLST(source, t);
  WRITELN('wrong')
END.
