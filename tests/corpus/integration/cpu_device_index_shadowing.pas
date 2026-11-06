{ DIALECT: extended }
{ NEW-8: in CPU DEVICE code a user declaration spelled like a device index
  builtin hides it (the local VAR threadidx_x, the FUNCTION BLOCKDIM_Y),
  and an unhidden builtin still reads the launch geometry. Six launches
  (2 blocks of 3 threads) each add BLOCKIDX_X * 10 + THREADIDX_X (0+1+2
  and 10+11+12, 36 in all), Shadowed (100 each) and BLOCKDIM_Y (1000
  each): 6636. }
(*$INCLUDE:'cpu_device_index_shadowing.inc'*)
PROGRAM CPUDEVICEINDEXSHADOWING(output);
USES INDEXSHADOWU (TALLY);
TYPE PINT = ^INTEGER32;
VAR cell: PINT;
BEGIN
  NEW(cell);
  cell^ := 0;
  LAUNCH(TALLY, 2, 3, cell);
  WRITELN(cell^);
  DISPOSE(cell)
END.
