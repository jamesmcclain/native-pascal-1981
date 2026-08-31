{ DIALECT: extended }
PROGRAM VectorLaneMismatch(output);
{ Elementwise operators require both operands to be the identical VECTOR
  type. The coarse typechecker model sees only a bare VECTOR kind, so a
  lane-count mismatch is caught in codegen (same tc-approximate /
  cg-is-the-backstop split as SETs). }
TYPE
  V4I = VECTOR [4] OF INTEGER32;
  V8I = VECTOR [8] OF INTEGER32;
VAR
  a: V4I;
  b: V8I;
  c: V4I;
BEGIN
  c := a + b
END.
