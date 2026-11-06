{ DIALECT: vintage }
{ A value formal and a local are valid FOR control variables. A reference
  formal is rejected (see for_ref_param_rejected). }
PROGRAM for_value_param_ok(OUTPUT);
PROCEDURE pval(i: INTEGER);
VAR j: INTEGER;
BEGIN
  FOR i := 1 TO 2 DO WRITELN(i);
  FOR j := 3 TO 4 DO WRITELN(j)
END;
VAR k: INTEGER;
BEGIN
  pval(k);
  FOR k := 5 TO 6 DO WRITELN(k)
END.
