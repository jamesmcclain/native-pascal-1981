{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NEW-8: in NVPTX code a local VAR threadidx_x and a module-level FUNCTION
  BlockIdx_X hide those device index builtins, so neither special
  register is read; the unhidden THREADIDX_Y still reads %tid.y. }
{ CHECK: %tid.y }
{ CHECK-NOT: %tid.x }
{ CHECK-NOT: %ctaid.x }
DEVICE MODULE DeviceIndexShadow;
VAR
  [SPACE(GLOBAL)] x, y, z: INTEGER32;
FUNCTION BlockIdx_X: INTEGER32;
BEGIN
  BlockIdx_X := 11
END;
PROCEDURE go;
VAR
  threadidx_x: INTEGER32;
BEGIN
  threadidx_x := 7;
  x := THREADIDX_X;
  y := threadidx_y;
  z := blockidx_x
END;
.
