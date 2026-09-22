{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6: NVPTX returns the complete aggregate through one CUDA ABI buffer. }
{ CHECK: .func  (.param .align 4 .b8 func_retval0[8]) MakeSmall() }
{ CHECK: st.param.b32 }
{ CHECK: [func_retval0] }
DEVICE MODULE DeviceAggregateSmallReturn;
TYPE
  TRec = RECORD
    a, b: INTEGER32
  END;
FUNCTION MakeSmall: TRec;
VAR
  r: TRec;
BEGIN
  r.a := 1;
  r.b := 2;
  MakeSmall := r
END;
.
