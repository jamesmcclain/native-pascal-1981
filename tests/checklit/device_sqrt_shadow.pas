{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ A declared SQRT is an ordinary device function, not the unbound builtin. }
{ CHECK: .func  (.param .b64 func_retval0) SQRT( }
{ CHECK-NOT: .extern .func }
DEVICE MODULE DeviceSqrtShadow;
VAR
  [SPACE(GLOBAL)] x: REAL;
FUNCTION SQRT(v: REAL): REAL;
BEGIN
  SQRT := v * 2.0
END;
PROCEDURE go;
BEGIN
  x := SQRT(4.0)
END;
.
