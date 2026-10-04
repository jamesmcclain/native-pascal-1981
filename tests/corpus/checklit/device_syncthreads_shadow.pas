{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ A user-declared, parameterized SYNCTHREADS must shadow the zero-arg
  synchronization builtin: it type-checks as an ordinary call (an
  unshadowed SYNCTHREADS rejects any argument) and codegen emits a normal
  routine with a PTX .param, not a bar.sync barrier. Regression coverage
  for the builtin-dispatch-before-symbol-lookup bug the Gap 1 fix
  introduced. }
{ CHECK: .visible .func SYNCTHREADS( }
{ CHECK: .param .b32 SYNCTHREADS_param_0 }
{ CHECK-NOT: bar.sync }
DEVICE MODULE DeviceSyncthreadsShadow;
VAR
  [SPACE(GLOBAL)] x: INTEGER32;
PROCEDURE SYNCTHREADS(v: INTEGER32);
BEGIN
  x := v
END;
PROCEDURE go;
BEGIN
  SYNCTHREADS(7)
END;
.
