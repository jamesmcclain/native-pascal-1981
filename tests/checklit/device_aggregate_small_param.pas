{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6 characterization: an 8-byte aggregate is currently coerced to one
  64-bit NVPTX parameter rather than emitted as a byval buffer. }
{ CHECK: .param .b64 SumSmall_param_0 }
DEVICE MODULE DeviceAggregateSmallParam;
TYPE
  TRec = RECORD
    a, b: INTEGER32
  END;
FUNCTION SumSmall(r: TRec): INTEGER32;
BEGIN
  SumSmall := r.a + r.b
END;
.
