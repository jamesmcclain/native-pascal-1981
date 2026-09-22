{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6 characterization: a 12-byte aggregate currently becomes two
  coerced NVPTX parameters (64-bit plus 32-bit). }
{ CHECK: .param .b64 Sum12_param_0 }
{ CHECK: .param .b32 Sum12_param_1 }
DEVICE MODULE DeviceAggregate12ByteParam;
TYPE
  TInt3 = ARRAY [1..3] OF INTEGER32;
FUNCTION Sum12(a: TInt3): INTEGER32;
BEGIN
  Sum12 := a[1] + a[2] + a[3]
END;
.
