{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ WRD is a constant function in a CONST value and a bound (IBM manual
  5-9), folded to its WORD bit pattern: WRD(-2) is 65534 (11-8). A CONST
  naming a WRD CONST, with or without a sign, is a constant too. Each of
  these used to abort codegen with "IntLiteralValue: not a foldable
  integer constant". }
PROGRAM const_wrd(OUTPUT);
CONST
  W = WRD(5);
  D = W;
  E = -W;
  P = +W;
  M = WRD(-2);
  C = WRD('a');
  B = WRD(TRUE);
  K = WRD(MAXINT);
  Z = WRD(-32768);
  R = WRD(BYWORD(1, 2));
  A = M;
TYPE
  Small = WRD(1)..WRD(3);
VAR
  arr: ARRAY [WRD(0)..WRD(2)] OF INTEGER;
  x: Small;
  wv: WORD;
  i: INTEGER;
BEGIN
  WRITELN(W, ' ', D, ' ', E, ' ', P);
  WRITELN(M, ' ', C, ' ', B, ' ', K, ' ', Z, ' ', R, ' ', A);
  x := 3; arr[2] := 7;
  WRITELN(x, ' ', arr[2], ' ', LOWER(arr), ' ', UPPER(arr), ' ', LOWER(x), ' ', UPPER(x));
  wv := M; WRITELN(wv);
  wv := D + 1; WRITELN(wv);
  i := E; WRITELN(i)
END.
