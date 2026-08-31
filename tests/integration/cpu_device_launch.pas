{ DIALECT: extended }
(*$INCLUDE:'cpu_device_launch.inc'*)
PROGRAM CPUDEVICELAUNCH(output);
USES INCREMENTU (INCREMENT);
TYPE PINT = ^INTEGER32;
VAR cell: PINT;
BEGIN
  NEW(cell);
  cell^ := 0;
  LAUNCH(INCREMENT, 2, 3, cell);
  WRITELN(cell^);
  DISPOSE(cell)
END.
