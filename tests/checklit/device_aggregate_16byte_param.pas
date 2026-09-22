{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ Gap 6: a 16-byte NVPTX value aggregate is one CUDA ABI parameter buffer. }
{ CHECK: .param .align 4 .b8 Sum16_param_0[16] }
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
