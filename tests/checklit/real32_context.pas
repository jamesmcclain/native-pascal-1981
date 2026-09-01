{ DIALECT: extended }
{ A REAL32-context literal is born as f32, not emitted as double and
  repaired by an assignment-side truncation. }
{ CHECK: fadd float }
{ CHECK-NOT: fptrunc }
PROGRAM Real32Context;
VAR
  a, b: REAL32;
  r: REAL;
BEGIN
  a := 1.25;
  b := a + 2.0;
  r := b
END.
