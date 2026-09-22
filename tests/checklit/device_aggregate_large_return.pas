{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6 characterization: a 20-byte aggregate return currently uses a
  pointer-sized hidden NVPTX parameter. This is a baseline, not ABI proof. }
{ CHECK: .func MakeLarge( }
{ CHECK: .param .b64 MakeLarge_param_0 }
DEVICE MODULE DeviceAggregateLargeReturn;
TYPE
  TRec = RECORD
    a, b, c, d, e: INTEGER32
  END;
FUNCTION MakeLarge: TRec;
VAR
  r: TRec;
BEGIN
  r.a := 1;
  r.b := 2;
  r.c := 3;
  r.d := 4;
  r.e := 5;
  MakeLarge := r
END;
.
