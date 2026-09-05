{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ CHECK: .param .align 8 .b8 Sum_param_0[20] }
DEVICE MODULE DeviceRecordByVal;
TYPE
  TRec = RECORD
    a, b, c, d, e: INTEGER32
  END;
FUNCTION Sum(r: TRec): INTEGER32;
BEGIN
  Sum := r.a + r.b + r.c + r.d + r.e
END;
.
