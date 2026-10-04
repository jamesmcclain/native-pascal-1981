{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6: NVPTX returns the complete aggregate through one CUDA ABI buffer. }
{ CHECK: .func  (.param .align 4 .b8 func_retval0[20]) MakeLarge() }
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
