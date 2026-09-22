{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6 characterization: an 8-byte aggregate return currently uses a
  64-bit NVPTX return parameter. This is a baseline, not an ABI endorsement. }
{ CHECK: .func  (.param .b64 func_retval0) MakeSmall() }
{ CHECK: st.param.b64 }
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
