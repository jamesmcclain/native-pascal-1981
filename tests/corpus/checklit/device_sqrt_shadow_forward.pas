{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ A FORWARD-declared SQRT is a definition this compiland still owes, not an
  unbound libm import: the call in `go' is sited while has_body is still
  FALSE, and must not be mistaken for the builtin the guard rejects. }
{ CHECK: .func  (.param .b64 func_retval0) SQRT( }
{ CHECK-NOT: .extern .func }
DEVICE MODULE DeviceSqrtShadowForward;
VAR
  [SPACE(GLOBAL)] x: REAL;
FUNCTION SQRT(v: REAL): REAL; FORWARD;
PROCEDURE go;
BEGIN
  x := SQRT(4.0)
END;
FUNCTION SQRT(v: REAL): REAL;
BEGIN
  SQRT := v * 2.0
END;
.
