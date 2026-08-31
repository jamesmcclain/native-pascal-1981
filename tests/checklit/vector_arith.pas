{ DIALECT: extended }
{ Elementwise operators lower to LLVM's native vector instructions -- one
  instruction per operator, no per-lane scalar loop. Pins the float add,
  an integer multiply, a bitwise mask op, and the two unary forms
  (fneg for a float vector, xor for a NOT). }
{ CHECK: fadd <4 x float> }
{ CHECK: mul <8 x i32> }
{ CHECK: and <4 x i8> }
{ CHECK: fneg <4 x float> }
{ CHECK: xor <8 x i32> }
PROGRAM VArith(output);
TYPE
  V4F = VECTOR [4] OF REAL32;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
VAR
  a, b, c: V4F;
  iv, iw: V8I;
  m, n: M4;
BEGIN
  a := VSPLAT(1.0, V4F);
  b := VSPLAT(2.0, V4F);
  c := a + b;
  c := -a;
  iv := VSPLAT(3, V8I);
  iw := iv * iv;
  iw := NOT iv;
  m := VSPLAT(TRUE, M4);
  n := m AND m;
  WRITELN(c[0]:0:2, ' ', iw[0], ' ', n[0])
END.
