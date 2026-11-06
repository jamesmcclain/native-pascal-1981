{ A STRING(n) capacity is 1..65535 and an LSTRING(n) capacity 0..65535 in
  the vintage dialect, whether n is a literal, a CONST or a signed CONST,
  and n must be an integer constant. STRING(-3) used to compile to a
  4 GiB array that failed at link time, and STRING(-N) to a bare STRING. }
PROGRAM string_capacity_bad(OUTPUT);
CONST N = 3; M = -N; C = 'A'; Z = 0;
VAR
  a: STRING(-3);
  b: STRING(-N);
  vc: LSTRING(M);
  d: STRING(0);
  e: LSTRING(-1);
  f: STRING(C);
  h: LSTRING(70000);
  i: STRING(Z);
  j: LSTRING(4294967293);
  k: STRING(-C);
BEGIN END.
