{ DIALECT: vintage extended }
{ A set's base type must have ordinals in 0..255 (IBM manual 6-24). Every
  spelling of the bounds gets the same located error at the declaration:
  SET OF -3..3 used to fail only at run time ("set element outside
  0..255"), and SET OF -N..N with "Cannot determine set element base
  type" at each use. }
PROGRAM set_base_range_bad(OUTPUT);
CONST N = 3; M = -N; H = 300; Lo = 10;
TYPE
  R = M..N;
  Wide = Lo..H;
  Bad = SET OF -3..3;
VAR
  a: SET OF -3..3;
  b: SET OF -N..N;
  c: SET OF M..N;
  d: SET OF R;
  e: SET OF 0..H;
  f: SET OF Wide;
  g: SET OF INTEGER;
  k: SET OF WORD;
BEGIN
  b := [1];
  WRITELN(1 IN b)
END.
