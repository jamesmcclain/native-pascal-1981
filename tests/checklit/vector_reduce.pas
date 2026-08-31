{ DIALECT: extended }
{ Horizontal reductions lower to the portable llvm.vector.reduce.* family,
  one call each, the intrinsic name mangled with the vector type. Float
  VSUM is ordered: it passes a 0.0 start operand and carries no reassoc. }
{ CHECK: call double @llvm.vector.reduce.fadd.v4f64(double 0 }
{ CHECK: call i32 @llvm.vector.reduce.add.v8i32(<8 x i32> }
{ CHECK: call i32 @llvm.vector.reduce.smax.v8i32(<8 x i32> }
{ CHECK: call i8 @llvm.vector.reduce.or.v4i8(<4 x i8> }
PROGRAM VReduceShape(output);
TYPE
  V4D = VECTOR [4] OF REAL;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
VAR
  d: V4D;
  iv: V8I;
  m: M4;
BEGIN
  d := VSPLAT(1.5, V4D);
  iv := VSPLAT(3, V8I);
  m := VSPLAT(TRUE, M4);
  WRITELN(VSUM(d):0:2, ' ', VSUM(iv), ' ', VMAX(iv));
  IF VANY(m) THEN WRITELN('y')
END.
