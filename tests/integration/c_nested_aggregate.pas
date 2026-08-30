{ DIALECT: extended }
{ Nested RECORD-in-RECORD and a bare ARRAY-by-value [C] parameter, at both
  COERCED (<=16 bytes) and MEMORY (>16 bytes) sizes -- SysVAggClass and the
  byval/coercion paths only ever see a flat leaf walk (WalkTypeLeaves), so
  nesting must not change the classification or the values that cross the
  ABI. Callees in c_nested_aggregate.c. }
PROGRAM CNestedAggregate(output);
TYPE
  Inner = RECORD
    a, b: INTEGER32;
  END;
  { 8 + 4 = 12 bytes: COERCED, two eightbytes (one full, one half-used). }
  Outer = RECORD
    inner: Inner;
    c: INTEGER32;
  END;
  { 8 + 12 = 20 bytes: MEMORY. }
  BigOuter = RECORD
    inner: Inner;
    pad: ARRAY [1..3] OF INTEGER32;
  END;
  { A bare ARRAY (not wrapped in a RECORD) at both class sizes. }
  SmallVec = ARRAY [1..2] OF INTEGER32;  { 8 bytes: COERCED. }
  BigVec = ARRAY [1..20] OF INTEGER32;   { 80 bytes: MEMORY. }

FUNCTION outer_sum(o: Outer): CINT [C]; EXTERN;
FUNCTION big_outer_sum(o: BigOuter): CINT [C]; EXTERN;
FUNCTION small_vec_sum(v: SmallVec): CINT [C]; EXTERN;
FUNCTION big_vec_sum(v: BigVec): CINT [C]; EXTERN;
FUNCTION make_outer(a, b, c: CINT): Outer [C]; EXTERN;

VAR
  o, o2: Outer;
  bo: BigOuter;
  sv: SmallVec;
  bv: BigVec;
  i: INTEGER;
BEGIN
  o.inner.a := 1;
  o.inner.b := 2;
  o.c := 3;
  WRITELN(outer_sum(o));  { 6 }

  bo.inner.a := 10;
  bo.inner.b := 20;
  bo.pad[1] := 1;
  bo.pad[2] := 2;
  bo.pad[3] := 3;
  WRITELN(big_outer_sum(bo));  { 36 }

  sv[1] := 100;
  sv[2] := 200;
  WRITELN(small_vec_sum(sv));  { 300 }

  FOR i := 1 TO 20 DO bv[i] := i;
  WRITELN(big_vec_sum(bv));  { 210 }

  o2 := make_outer(7, 8, 9);
  WRITELN(o2.inner.a, ' ', o2.inner.b, ' ', o2.c);  { 7 8 9 }
END.
