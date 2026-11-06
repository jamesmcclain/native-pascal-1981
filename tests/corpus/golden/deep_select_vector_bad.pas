{ DIALECT: extended }
{ NEW-12: the anonymous VECTOR [8] element behind m^[0]^[1] (selector
  depth 4) keeps its lane count: lane 7 is accepted and lane 8 is a
  located typecheck error; its REAL32 lanes take no CHAR. }
PROGRAM DeepSelectVectorBad(OUTPUT);
TYPE
  PV = ^ARRAY [1..2] OF VECTOR [8] OF REAL32;
  SV = SUPER ARRAY [0..*] OF PV;
VAR
  m: ^SV;
BEGIN
  NEW(m, 0);
  NEW(m^[0]);
  m^[0]^[1][7] := 1.0;
  m^[0]^[1][8] := 1.0;
  m^[0]^[2][0] := 'c'
END.
