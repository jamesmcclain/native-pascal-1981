{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-12: anonymous enumerations reached at selector depth 4 and 5, below
  the three levels the typechecker's flat metadata keeps. The record behind
  l^[i]^ declares its enumerations inline, and m^[i]^[j] reaches an inline
  enumeration as an array element. Their members are constants of their
  own type: stores, comparisons, CASE labels, SUCC/PRED/ORD, copies
  between deep and shallow designators of one type and an enumeration
  index all type-check with the declared identity. }
PROGRAM DeepSelectEnum(OUTPUT);
TYPE
  PR = ^R;
  R = RECORD
    color: (red, green, blue);
    shade: ARRAY [1..2] OF (light, dark);
    n: INTEGER
  END;
  SA = SUPER ARRAY [0..*] OF PR;
  PSA = ^SA;
  PM = ^ARRAY [1..3] OF (north, south, east);
  SM = SUPER ARRAY [0..*] OF PM;
  PSM = ^SM;
VAR
  l: PSA;
  m: PSM;
  i: INTEGER;
  counts: ARRAY [north..east] OF INTEGER;
  here: PM;
BEGIN
  NEW(l, 2);
  FOR i := 0 TO 2 DO
  BEGIN
    NEW(l^[i]);
    l^[i]^.color := red;
    l^[i]^.shade[1] := light;
    l^[i]^.shade[2] := dark;
    l^[i]^.n := i
  END;
  l^[1]^.color := SUCC(l^[0]^.color);
  l^[2]^.color := blue;
  l^[0]^.shade[1] := l^[2]^.shade[2];
  FOR i := 0 TO 2 DO
  BEGIN
    CASE l^[i]^.color OF
      red: WRITE('red');
      green: WRITE('green');
      blue: WRITE('blue')
    END;
    IF l^[i]^.shade[1] = dark THEN WRITE(' dark') ELSE WRITE(' light');
    IF l^[i]^.color > red THEN WRITE(' >red');
    WRITELN(' ', ORD(l^[i]^.color):1)
  END;

  NEW(m, 1);
  NEW(m^[0]);
  NEW(m^[1]);
  m^[0]^[1] := north;
  m^[0]^[2] := east;
  m^[0]^[3] := PRED(m^[0]^[2]);
  here := m^[0];
  m^[1]^[1] := here^[3];
  m^[1]^[2] := m^[0]^[1];
  m^[1]^[3] := m^[1]^[1];
  counts[north] := 0; counts[south] := 0; counts[east] := 0;
  FOR i := 1 TO 3 DO
  BEGIN
    counts[m^[0]^[i]] := counts[m^[0]^[i]] + 1;
    counts[m^[1]^[i]] := counts[m^[1]^[i]] + 10
  END;
  WRITELN('counts ', counts[north]:1, ' ', counts[south]:1, ' ', counts[east]:1);
  IF m^[1]^[1] = south THEN WRITELN('south via alias')
END.
