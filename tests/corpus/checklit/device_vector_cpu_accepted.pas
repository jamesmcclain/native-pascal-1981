{ DIALECT: extended }
{ CHECK: fmul <4 x float> }
DEVICE MODULE DeviceVectorCpuAccepted;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V4FAlias = V4F;
  V4FArray = ARRAY [0..1] OF V4FAlias;
VAR
  out_data: V4FArray;
PROCEDURE square;
VAR
  u: V4FAlias;
BEGIN
  u := VSPLAT(2.0, V4FAlias);
  out_data[0] := u * u
END;
.
