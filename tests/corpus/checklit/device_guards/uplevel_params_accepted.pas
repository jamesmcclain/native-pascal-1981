{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NEW-26: a nested DEVICE routine that takes what it needs as parameters
  still compiles; DEVICE routines keep their signatures (no static link). }
{ CHECK: .func Inner( }
{ CHECK: .param .b32 Inner_param_0 }
{ CHECK-NOT: Inner_param_1 }
DEVICE MODULE UplevelParamsAccepted;
VAR out_data: ARRAY [0..3] OF INTEGER32;
PROCEDURE go;
VAR k: INTEGER32;
  PROCEDURE Inner(v: INTEGER32);
  BEGIN
    out_data[0] := v
  END;
BEGIN
  k := 3;
  Inner(k)
END;
.
