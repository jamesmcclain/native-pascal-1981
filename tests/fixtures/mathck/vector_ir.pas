{$MATHCK-}
{ INTEGER VECTOR lanes under MATHCK-: the O0 IR keeps the vector add, sub,
  mul and llvm.vector.reduce.add with no overflow intrinsic or failure call;
  DIV and MOD never reach a vector sdiv/srem (each lane is guarded, 8
  pas_math_zero calls). Checked by tests/mathck_vector.sh. }
PROGRAM VectorMath;
TYPE V = VECTOR [4] OF INTEGER;
VAR a, b, c: V; t, s: INTEGER;
BEGIN
c := a + b; c := a - b; c := a * b; c := -a; t := VSUM(a);
c := a DIV b; c := a MOD b;
END.
