{ DIALECT: extended }
{ OPT: 0 2 }
{ NEW-32: in the extended dialect an integer subrange whose upper bound is
  above 65535 has the host INTEGER32, as an array index range does
  (NEW-5). The typechecker used to give it the host INTEGER, so `r := i32'
  for 0..100000 was rejected, and codegen stopped at any bound above
  32767. Covers the 65535/65536 edge, a CONST bound, an INTEGER32 store,
  WRITE, comparisons, arithmetic, parameters, a function result, an array
  indexed by the subrange type and FOR. }
PROGRAM ExtendedWideSubrangeHosts(OUTPUT);
CONST
  LIM = 100000;
TYPE
  Wide = 0..LIM;
  Last16 = 0..65535;
  First32 = 0..65536;
  Mid = 65530..65540;
VAR
  r: 0..100000;
  v: Wide;
  l16: Last16;
  f32: First32;
  m: Mid;
  i32: INTEGER32;
  w: WORD;
  a: ARRAY [Mid] OF INTEGER32;
  n: INTEGER;

FUNCTION Half(x: Wide): Wide;
BEGIN
  Half := x DIV 2
END;

PROCEDURE Bump(VAR x: Wide);
BEGIN
  x := x + 1
END;

BEGIN
  i32 := 99999;
  r := i32;
  WRITELN(r);
  r := 100000;
  WRITELN(r, ' ', UPPER(r), ' ', r - 1, ' ', r DIV 3);
  i32 := r;
  WRITELN(i32);
  l16 := 65535;
  f32 := 65536;
  w := l16;
  WRITELN(l16, ' ', f32, ' ', w, ' ', UPPER(l16), ' ', UPPER(f32));
  v := 70000;
  WRITELN(v:7, '|');
  IF v > 65535 THEN WRITELN('gt');
  IF v < r THEN WRITELN('lt');
  WRITELN(Half(v));
  Bump(v);
  WRITELN(v);
  FOR m := 65530 TO 65540 DO a[m] := m - 65530;
  WRITELN(a[65530], ' ', a[65540], ' ', LOWER(a), ' ', UPPER(a));
  n := 0;
  FOR v := 99998 TO UPPER(v) DO n := n + 1;
  WRITELN(n)
END.
