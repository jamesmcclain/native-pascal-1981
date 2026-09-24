{ DIALECT: extended }
{ VLOAD/VSTORE on a NEW-allocated SUPER ARRAY pointee: one i128 whole-lane
  range check (non-NIL, idx >= lo, idx+n-1 <= the i64 header bound) guards
  each access, and failure calls a noreturn runtime diagnostic. VSTORE's
  per-lane stores all sit after its single check. }
{ CHECK-COUNT: 2 call void @pas_vector_nil_error }
{ CHECK-COUNT: 2 call void @pas_vector_range_error }
{ CHECK: sext i32 }
{ CHECK: to i128 }
{ CHECK: icmp sle i128 }
{ CHECK: load <8 x float>, ptr }
{ CHECK: unreachable }
PROGRAM VSuperDerefShape(output);
TYPE
  FB = SUPER ARRAY [0..*] OF REAL32;
  PFB = ^FB;
  V8F = VECTOR [8] OF REAL32;
VAR
  p: PFB;
  v: V8F;
  i: INTEGER32;
BEGIN
  NEW(p, 31);
  i := 8;
  v := VLOAD(p^, i, V8F);
  VSTORE(p^, i, v);
  WRITELN(v[0]:0:2)
END.
