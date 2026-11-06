{ DIALECT: vintage extended }
{ NEW-8: a user VAR, CONST or routine spelled like a DEVICE index builtin
  (THREADIDX_X .. GRIDDIM_Z) hides it, as a user declaration hides any
  predeclared identifier. Host code used to reject these names as
  device builtins, and codegen lowered them as builtins whatever was
  declared. An undeclared one is still rejected in host code
  (golden/24_device_index_host_rejected). }
PROGRAM DeviceIndexNameShadowing(OUTPUT);
CONST
  griddim_z = 7;
TYPE
  Pair = RECORD
    blockidx_x: INTEGER;
    other: INTEGER
  END;
VAR
  threadidx_x: INTEGER;
  BlockIdx_Y: CHAR;
  r: Pair;

FUNCTION blockdim_x: INTEGER;
BEGIN
  blockdim_x := 42
END;

PROCEDURE Local;
VAR
  GRIDDIM_Y: INTEGER;
BEGIN
  GRIDDIM_Y := 9;
  WRITELN(GridDim_Y + griddim_z)
END;

BEGIN
  threadidx_x := 5;
  BlockIdx_Y := 'q';
  WRITELN(THREADIDX_X, ' ', blockidx_y, ' ', GRIDDIM_Z, ' ', BlockDim_X);
  Local;
  r.blockidx_x := 3;
  r.other := 4;
  WITH r DO
    WRITELN(blockidx_x + other)
END.
