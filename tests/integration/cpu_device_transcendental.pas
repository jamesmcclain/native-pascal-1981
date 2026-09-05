{ DIALECT: extended }
(*$INCLUDE:'cpu_device_transcendental.inc'*)
PROGRAM CPUDEVICETRANSCENDENTAL(output);
USES ACCUMULATEU (ACCUMULATE);
TYPE PREAL = ^REAL;
VAR cell: PREAL;
BEGIN
  NEW(cell);
  cell^ := 0.0;
  LAUNCH(ACCUMULATE, 2, 3, cell);
  WRITELN(TRUNC(cell^));
  DISPOSE(cell)
END.
