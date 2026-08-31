{ DIALECT: extended }
{ A lanewise comparison is icmp/fcmp -> <n x i1> then zext to the <n x i8>
  a BOOLEAN vector is stored as; VSELECT truncs that mask back to <n x i1>
  and emits a vector select. }
{ CHECK: icmp slt <4 x i32> }
{ CHECK: zext <4 x i1> }
{ CHECK: fcmp oge <4 x double> }
{ CHECK: trunc <4 x i8> }
{ CHECK: select <4 x i1> }
PROGRAM VSelectShape(output);
TYPE
  V4I = VECTOR [4] OF INTEGER32;
  V4D = VECTOR [4] OF REAL;
  M4  = VECTOR [4] OF BOOLEAN;
VAR
  a, b, r: V4I;
  d, e, s: V4D;
  mi: M4;
BEGIN
  a := VSPLAT(1, V4I);
  b := VSPLAT(2, V4I);
  mi := a < b;
  r := VSELECT(mi, a, b);
  d := VSPLAT(3.0, V4D);
  e := VSPLAT(2.0, V4D);
  s := VSELECT(d >= e, d, e);
  WRITELN(r[0], ' ', s[0]:0:2)
END.
