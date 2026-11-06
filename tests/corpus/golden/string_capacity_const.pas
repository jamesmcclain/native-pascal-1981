{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ A STRING/LSTRING capacity may be a CONST name, a +signed one or a
  constant call. A CONST name used to give a capacity of 0, and a call a
  bare (256-character) string. }
PROGRAM string_capacity_const(OUTPUT);
CONST N = 3; W = WRD(4); Z = 0; B = BYWORD(0, 5);
TYPE T = STRING(+N);
VAR
  vt: STRING(N); l: LSTRING(N); p: T; vw: STRING(W); vz: LSTRING(Z);
  y: LSTRING(WRD(6)); o: STRING(ORD('a')); b2: LSTRING(B);
BEGIN
  vt := 'abc'; l := 'ab'; p := 'xyz'; vw := 'wxyz';
  WRITELN(UPPER(vt), ' ', UPPER(l), ' ', UPPER(p), ' ', UPPER(vw), ' ',
          UPPER(vz), ' ', UPPER(y), ' ', UPPER(o), ' ', UPPER(b2));
  WRITELN(vt, ' ', l, ' ', p, ' ', vw, ' ', ORD(l[0]))
END.
