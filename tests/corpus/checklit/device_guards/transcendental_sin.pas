{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: SIN in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: SIN }
DEVICE MODULE SINDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := SIN(x) END;
.
