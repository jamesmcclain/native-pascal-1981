{ DIALECT: extended }
{ --target-cpu / --target-features are forwarded from the driver to the
  codegen stage as CLI options (never environment) and land on every
  function this compiland defines as LLVM string attributes -- the same
  mechanism clang uses. clang compiling the emitted .ll honours them, so
  no -march passthrough to clang is needed. }
{ CHECK-FLAGS: --target-cpu skylake-avx512 --target-features +avx512f,+avx512vl }
{ CHECK: "target-cpu"="skylake-avx512" }
{ CHECK: "target-features"="+avx512f,+avx512vl" }
{ CHECK: define void @Scale(<8 x i32> %0) #0 }
{ CHECK: define i32 @main(i32 %0, ptr %1) #0 }
PROGRAM VTargetCpu(output);
TYPE V8I = VECTOR [8] OF INTEGER32;
VAR a, b: V8I; i: INTEGER;
PROCEDURE Scale(v: V8I);
BEGIN
  WRITELN(v[0])
END;
BEGIN
  FOR i := 0 TO 7 DO a[i] := i;
  b := a * VSPLAT(3, V8I);
  Scale(b)
END.
