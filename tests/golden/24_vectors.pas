{ DIALECT: extended }
PROGRAM VectorTypes;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
  V4D = VECTOR [4] OF REAL;
VAR
  a, b: V4F;
  iv, iw: V8I;
  m: M4;
  d: V4D;
  i: INTEGER;
BEGIN
  { M0: declare, whole-vector assign, SIZEOF, LOWER/UPPER. }
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
  WRITELN(LOWER(m), ' ', UPPER(m));

  { M2a: lane write then read, every lane, for a float, an integer and a
    mask vector; a variable lane index (unchecked) and a lane-to-lane
    assignment. }
  FOR i := 0 TO 3 DO d[i] := (i + 1) * 1.5;
  FOR i := 0 TO 3 DO WRITELN('d[', i, ']=', d[i]:0:2);
  WRITELN('d1+d3=', (d[1] + d[3]):0:2);

  FOR i := 0 TO 7 DO iv[i] := i * i;
  FOR i := 0 TO 7 DO WRITE(iv[i], ' ');
  WRITELN;
  iv[7] := iv[0] + iv[3];
  WRITELN('iv7=', iv[7]);

  m[0] := TRUE;
  m[1] := FALSE;
  m[2] := TRUE;
  m[3] := FALSE;
  FOR i := 0 TO 3 DO
    IF m[i] THEN WRITE('T ') ELSE WRITE('F ');
  WRITELN
END.
