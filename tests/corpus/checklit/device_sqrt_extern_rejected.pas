{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ The other side of device_sqrt_shadow_forward.pas: an EXTERN SQRT promises
  its body to another compiland, so nothing here will ever define it and the
  call would leave an unresolved transcendental in the PTX. }
{ CHECK-FAIL: transcendental math function is not supported in DEVICE code: SQRT }
DEVICE MODULE DeviceSqrtExternRejected;
VAR
  [SPACE(GLOBAL)] x: REAL;
FUNCTION SQRT(v: REAL): REAL; EXTERN;
PROCEDURE go;
BEGIN
  x := SQRT(4.0)
END;
.
