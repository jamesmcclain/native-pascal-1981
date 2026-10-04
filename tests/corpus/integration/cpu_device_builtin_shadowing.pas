{ DIALECT: extended }
(*$INCLUDE:'cpu_device_builtin_shadowing.inc'*)
PROGRAM CPUDEVICEBUILTINSHADOWING(output);
USES ACCUMULATEU (ACCUMULATE);
TYPE PREAL = ^REAL;
VAR cell: PREAL;
BEGIN
  NEW(cell);
  cell^ := 0.0;
  LAUNCH(ACCUMULATE, 1, 1, cell);
  WRITELN(TRUNC(cell^));
  DISPOSE(cell)
END.
