PROGRAM publication;
VAR t: LSTRING(3);
PROCEDURE Arm(p: ADRMEM) [C]; EXTERN;
PROCEDURE Tick [C]; EXTERN;
FUNCTION source: LSTRING(2);
BEGIN
  Tick;
  source := 'xy'
END;
BEGIN
  t := 'abc';
  t := 'ab';
  Arm(ADR t);
  {$RANGECK+}
  CONCAT(t, source);
  WRITELN('wrong')
END.
