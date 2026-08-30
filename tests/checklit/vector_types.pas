{ DIALECT: extended }
{ Pins the vector representation decisions that fail silently if wrong:
  natural vector ABI alignment on the emitted allocas (TypeAlignBytes must
  agree with LLVM's datalayout exactly -- see TypeSizeBytes/TypeAlignBytes),
  and the <n x i8> storage rule for BOOLEAN vectors. }
{ CHECK: alloca <4 x float>, align 16 }
{ CHECK: alloca <8 x i32>, align 32 }
{ CHECK: alloca <4 x i8>, align 4 }
PROGRAM VTypes;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
VAR
  gv: V4F;
PROCEDURE Touch;
VAR
  a, b: V4F;
  iv: V8I;
  m: M4;
BEGIN
  b := a;
  gv := b;
  iv := iv;
  m := m
END;
BEGIN
  Touch
END.
