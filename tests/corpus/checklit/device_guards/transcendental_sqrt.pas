{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: SQRT in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: SQRT }
DEVICE MODULE SQRTDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := SQRT(x) END;
.
