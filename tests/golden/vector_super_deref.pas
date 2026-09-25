{ DIALECT: extended }
PROGRAM VectorSuperDeref(output);
{ VLOAD/VSTORE through a dereferenced NEW-allocated SUPER ARRAY (p^), with a
  nonzero lower bound: the first and last legal offsets, constant and
  variable indices of several integer widths, and a scalar tail beyond the
  last full vector. The whole lane range is checked at run time against
  LOWER(p^)..UPPER(p^); these accesses are all in range. }
TYPE
  FB = SUPER ARRAY [1..*] OF REAL32;
  PFB = ^FB;
  V8F = VECTOR [8] OF REAL32;
  V4F = VECTOR [4] OF REAL32;
  HOLDER = RECORD tag: INTEGER; buf: PFB; END;
VAR
  p: PFB;
  h: HOLDER;
  v: V8F;
  w: V4F;
  i: INTEGER32;
  j: INTEGER;
  k: WORD;
  q: INTEGER64;
  n: INTEGER32;
BEGIN
  n := 21;
  NEW(p, n);                              { p^[1..21] }
  FOR i := 1 TO n DO p^[i] := i;
  v := VLOAD(p^, 1, V8F);                 { first legal offset }
  WRITELN(v[0]:0:1, ' ', v[7]:0:1);
  i := n - 7;
  v := VLOAD(p^, i, V8F);                 { last legal offset: 14..21 }
  WRITELN(v[0]:0:1, ' ', v[7]:0:1);
  VSTORE(p^, 1, VSPLAT(-1.0, V8F));       { lanes 1..8 }
  j := 14;
  VSTORE(p^, j, VSPLAT(-2.0, V8F));       { lanes 14..21, INTEGER index }
  k := 9;
  w := VLOAD(p^, k, V4F);                 { WORD index: 9..12 untouched }
  WRITELN(w[0]:0:1, ' ', w[3]:0:1);
  q := 13;
  w := VLOAD(p^, q, V4F);                 { INTEGER64 index: 13..16 }
  WRITELN(w[0]:0:1, ' ', w[1]:0:1, ' ', w[3]:0:1);
  FOR i := 1 TO n DO WRITE(p^[i]:0:0, ' ');
  WRITELN;
  WRITELN(LOWER(p^), ' ', UPPER(p^));
  { Through a record field: h.buf^ is also a NEW-allocated pointee. }
  h.tag := 7;
  h.buf := p;
  VSTORE(h.buf^, 5, VSPLAT(3.0, V4F));
  w := VLOAD(h.buf^, 4, V4F);
  WRITELN(w[0]:0:1, ' ', w[1]:0:1, ' ', w[3]:0:1);
  DISPOSE(p)
END.
