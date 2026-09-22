{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6: a 12-byte NVPTX value aggregate is one CUDA ABI parameter buffer. }
{ CHECK: .param .align 4 .b8 Sum12_param_0[12] }
DEVICE MODULE DeviceAggregate12ByteParam;
TYPE
  TInt3 = ARRAY [1..3] OF INTEGER32;
FUNCTION Sum12(a: TInt3): INTEGER32;
BEGIN
  Sum12 := a[1] + a[2] + a[3]
END;
.
