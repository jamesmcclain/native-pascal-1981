PROGRAM BoundFixedPointerRejected(output);
TYPE A = ARRAY [2..5] OF INTEGER;
     PA = ^A;
VAR p: PA;
BEGIN
  WRITELN(UPPER(p^))
END.
