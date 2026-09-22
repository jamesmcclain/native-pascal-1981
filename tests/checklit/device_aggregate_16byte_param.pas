{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6 characterization: a 16-byte aggregate currently becomes two
  coerced 64-bit NVPTX parameters. }
{ CHECK: .param .b64 Sum16_param_0 }
{ CHECK: .param .b64 Sum16_param_1 }
DEVICE MODULE DeviceAggregate16ByteParam;
TYPE
  TRec = RECORD
    a, b, c, d: INTEGER32
  END;
FUNCTION Sum16(r: TRec): INTEGER32;
BEGIN
  Sum16 := r.a + r.b + r.c + r.d
END;
.
