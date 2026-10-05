{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: ARCTAN in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: ARCTAN }
DEVICE MODULE ARCTANDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := ARCTAN(x) END;
.
