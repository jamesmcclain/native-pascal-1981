(*$INCLUDE:'unit_exported_var.inc'*)
PROGRAM UnitExportedVar(output);
USES unitstate;
BEGIN
  Counter := 40;
  Increment;
  WRITELN(Counter);
END.
