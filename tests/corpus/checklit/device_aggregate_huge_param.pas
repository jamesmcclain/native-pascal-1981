{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NEW-35r: a non-kernel NVPTX by-value aggregate parameter of 1,024 bytes or
  more is passed by pointer to a caller-side copy (llvm.memcpy) instead of a
  .param buffer, matching the sret lowering for large results. Smaller value
  parameters keep the .param buffer (device_record_byval). }
{ CHECK: .func  (.param .b32 func_retval0) ConsumeHuge( }
{ CHECK: .param .b64 ConsumeHuge_param_0 }
{ CHECK: call.uni (retval0), ConsumeHuge, (param0); }
{ CHECK-NOT: .param .align 4 .b8 ConsumeHuge_param_0[ }
{$MATHCK-}
DEVICE MODULE DeviceAggregateHugeParam;
TYPE
  TRec = RECORD
    a: INTEGER32;
    d: ARRAY [1..70000] OF CHAR
  END;
FUNCTION MakeHuge: TRec;
VAR
  r: TRec;
BEGIN
  r.a := 7;
  MakeHuge := r
END;
FUNCTION ConsumeHuge(r: TRec): INTEGER32;
BEGIN
  r.a := r.a + 1;
  ConsumeHuge := r.a
END;
FUNCTION Caller: INTEGER32;
VAR
  r: TRec;
  x: INTEGER32;
BEGIN
  r.a := 41;
  x := ConsumeHuge(r);
  Caller := x + ConsumeHuge(MakeHuge) + r.a
END;
.
