{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NEW-35: a device function result of 1,024 bytes or more is returned
  through a hidden sret pointer instead of the .param return buffer, which
  the NVPTX backend cannot lower at this size (codegen crashed). Smaller
  results keep the buffer (device_aggregate_large_return). }
{ CHECK: .func MakeHuge( }
{ CHECK: .param .b64 MakeHuge_param_0 }
{ CHECK: call.uni MakeHuge, (param0); }
{ CHECK-NOT: func_retval0) MakeHuge }
DEVICE MODULE DeviceAggregateHugeReturn;
TYPE
  TRec = RECORD
    a: INTEGER32;
    d: ARRAY [1..70000] OF CHAR
  END;
FUNCTION MakeHuge: TRec;
VAR
  r: TRec;
BEGIN
  r.a := 1;
  MakeHuge := r
END;
FUNCTION UseHuge: INTEGER32;
VAR
  r: TRec;
BEGIN
  r := MakeHuge;
  UseHuge := r.a
END;
.
