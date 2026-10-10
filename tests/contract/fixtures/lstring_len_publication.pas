PROGRAM publication;
TYPE Short = LSTRING(3);
VAR a: ARRAY[1..2] OF Short; big: LSTRING(255);
PROCEDURE Arm(p: ADRMEM) [C]; EXTERN;
PROCEDURE TargetTick [C]; EXTERN;
PROCEDURE SourceTick [C]; EXTERN;
FUNCTION idx: INTEGER;
BEGIN TargetTick; idx := 1 END;
FUNCTION source: CHAR;
BEGIN SourceTick; source := big.LEN END;
BEGIN
  a[1] := 'abc'; a[1] := 'ab'; a[2] := 'xyz';
  big := ''; big.LEN := CHR(200);
  Arm(ADR a);
  {$RANGECK+}
  a[idx].LEN := source;
  WRITELN('wrong')
END.
