{ DIALECT: extended }
{ NEW-26: nested routines inside a separately compiled UNIT
  implementation reach their enclosing routine's locals and formals. }
(*$INCLUDE:'uplevel_units.api.inc'*)
PROGRAM UplevelUnits(output);
USES uplevelapi;
VAR p: PCells; i: INTEGER;
BEGIN
  NEW(p, 4);
  FOR i := 1 TO 4 DO p^[i] := i;
  Scale(p, 4, 3);
  WRITELN(SumCells(p, 4));
  DISPOSE(p)
END.
