{ DIALECT: extended }
{ OPT: 0 2 }
{ NEW-12: anonymous VECTOR types reached at selector depth 4 to 6, below
  the three levels the typechecker's flat metadata keeps: a record field
  behind l^[i]^ and an array element m^[i]^[j]. They keep their element
  kind and lane count, so constant lanes up to n-1 are accepted (they were
  "Vector lane index out of range" with the lane count lost), lanes read
  and write their element type, and whole-vector operations type-check. }
PROGRAM DeepSelectVector(OUTPUT);
TYPE
  R = RECORD
    v: VECTOR [4] OF INTEGER32;
    flags: VECTOR [2] OF BOOLEAN
  END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
  PV = ^ARRAY [1..2] OF VECTOR [8] OF REAL32;
  SV = SUPER ARRAY [0..*] OF PV;
VAR
  l: ^SA;
  m: ^SV;
  i: INTEGER;
  total: INTEGER32;
BEGIN
  NEW(l, 1);
  NEW(l^[0]);
  NEW(l^[1]);
  FOR i := 0 TO 3 DO
  BEGIN
    l^[0]^.v[i] := i + 1;
    l^[1]^.v[i] := 10 * (i + 1)
  END;
  l^[0]^.v[3] := l^[0]^.v[3] + l^[1]^.v[0];
  l^[1]^.v := l^[0]^.v + l^[1]^.v;
  l^[0]^.flags[0] := TRUE;
  l^[0]^.flags[1] := l^[0]^.v[3] > 10;
  total := 0;
  FOR i := 0 TO 3 DO total := total + l^[1]^.v[i];
  WRITELN(l^[0]^.v[0]:1, ' ', l^[0]^.v[3]:1, ' ', l^[1]^.v[3]:1, ' ', total:1,
          ' ', l^[0]^.flags[0], ' ', l^[0]^.flags[1]);

  NEW(m, 0);
  NEW(m^[0]);
  FOR i := 0 TO 7 DO
  BEGIN
    m^[0]^[1][i] := i * 0.5;
    m^[0]^[2][i] := 2.0
  END;
  m^[0]^[2] := m^[0]^[1] * m^[0]^[2];
  WRITELN(m^[0]^[2][7]:0:1, ' ', m^[0]^[2][1]:0:1, ' ', LOWER(m^[0]^[1]):1,
          ' ', UPPER(m^[0]^[1]):1)
END.
