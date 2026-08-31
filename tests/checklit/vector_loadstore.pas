{ DIALECT: extended }
{ VLOAD is one wide load at element (not vector) alignment -- the array is
  only element-aligned and the index is arbitrary. VSTORE is per-lane
  extractelement + scalar store, each element-aligned, so no over-aligned
  vector store is emitted. }
{ CHECK: load <4 x float>, ptr }
{ CHECK: align 4 }
{ CHECK: extractelement <4 x float> }
{ CHECK: store float }
PROGRAM VLoadStoreShape(output);
TYPE V4F = VECTOR [4] OF REAL32;
VAR
  buf: ARRAY [0..15] OF REAL32;
  v: V4F;
  i: INTEGER;
BEGIN
  v := VSPLAT(1.0, V4F);
  VSTORE(buf, 4, v);
  i := 2;
  v := VLOAD(buf, i, V4F);
  WRITELN(v[0]:0:2)
END.
