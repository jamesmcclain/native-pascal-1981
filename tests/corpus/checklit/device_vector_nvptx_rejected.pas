{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK-FAIL: VECTOR types are not supported in DEVICE code compiled for NVPTX }
DEVICE MODULE DeviceVectorNvptxRejected;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V4FAlias = V4F;
  V4FArray = ARRAY [0..1] OF V4FAlias;
VAR
  out_data: V4FArray;
PROCEDURE square;
VAR
  u: V4F;
BEGIN
  u := VSPLAT(2.0, V4F);
  out_data[0] := u * u
END;
.
