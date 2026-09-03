{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK: .target sm_70 }
{ CHECK: bar.sync }
DEVICE MODULE DeviceSync;
VAR
  [SPACE(SHARED)] scratch: ARRAY [0..31] OF INTEGER32;
  [SPACE(GLOBAL)] out_data: ARRAY [0..31] OF INTEGER32;
PROCEDURE sync_block;
BEGIN
  scratch[THREADIDX_X] := THREADIDX_X;
  SYNCTHREADS;
  out_data[THREADIDX_X] := scratch[31 - THREADIDX_X];
  SYNCTHREADS
END;
.
