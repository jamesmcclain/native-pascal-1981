{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: LN in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: LN }
DEVICE MODULE LNDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := LN(x) END;
.
