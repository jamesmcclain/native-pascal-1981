{ DIALECT: extended }
{ USES binds a local name to a DEVICE unit's kernel: LAUNCH through the
  alias BUMPIT runs INCREMENT, whose real symbol the linked unit defines,
  and the alias does not hide the original name. }
(*$INCLUDE:'cpu_device_launch.inc'*)
PROGRAM CPUDEVICEUSESRENAME(output);
USES INCREMENTU (BUMPIT);
TYPE PINT = ^INTEGER32;
VAR cell: PINT;
BEGIN
  NEW(cell);
  cell^ := 0;
  LAUNCH(BUMPIT, 2, 3, cell);
  WRITELN(cell^);
  LAUNCH(INCREMENT, 1, 2, cell);
  WRITELN(cell^);
  DISPOSE(cell)
END.
