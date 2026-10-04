{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NVPTX has no libm: COS in DEVICE code is rejected, not called. }
{ CHECK-FAIL: codegen: transcendental math function is not supported in DEVICE code: COS }
DEVICE MODULE COSDevice;
VAR x: REAL;
PROCEDURE go;
BEGIN x := COS(x) END;
.
