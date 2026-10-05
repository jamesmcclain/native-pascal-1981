{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: EXP in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: EXP }
DEVICE MODULE EXPDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := EXP(x) END;
.
