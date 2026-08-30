{ DIALECT: extended }
PROGRAM VectorTypes;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
VAR
  a, b: V4F;
  iv, iw: V8I;
  m: M4;
BEGIN
  a := b;
  b := a;
  iw := iv;
  m := m;
  WRITELN(SIZEOF(V4F));
  WRITELN(SIZEOF(a));
  WRITELN(SIZEOF(V8I));
  WRITELN(SIZEOF(M4));
  WRITELN(SIZEOF(b));
  WRITELN(LOWER(a), ' ', UPPER(a));
  WRITELN(LOWER(iv), ' ', UPPER(iv));
  WRITELN(LOWER(m), ' ', UPPER(m))
END.
