{ DIALECT: extended }
{ Without --device-triple a DEVICE compiland is an ordinary host module that
  links libm, so the NVPTX ban does not apply: each function calls libm. }
{ CHECK: @sqrt( }
{ CHECK: @sin( }
{ CHECK: @cos( }
{ CHECK: @log( }
{ CHECK: @exp( }
{ CHECK: @atan( }
DEVICE MODULE CpuTranscendental;
VAR x: REAL;
PROCEDURE go;
BEGIN x := SQRT(x); x := SIN(x); x := COS(x); x := LN(x); x := EXP(x); x := ARCTAN(x) END;
.
