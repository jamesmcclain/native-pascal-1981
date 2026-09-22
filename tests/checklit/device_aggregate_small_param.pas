{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6: NVPTX value aggregates use CUDA's aligned parameter buffer ABI,
  not host SysV register-piece coercion. }
{ CHECK: .param .align 4 .b8 SumSmall_param_0[8] }
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
