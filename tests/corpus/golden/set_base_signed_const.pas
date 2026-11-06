{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ A signed CONST name is a set base or array index bound like a literal:
  SET OF -K..N (K = -1) is SET OF 1..3, and ARRAY [R] for R = -N..N has
  bounds -3..3. Both used to be type errors. }
PROGRAM set_base_signed_const(OUTPUT);
CONST K = -1; N = 3;
TYPE R = -N..N; ST = SET OF -K..N;
VAR
  s: ST;
  t: SET OF -K..N;
  a: ARRAY [R] OF INTEGER;
  b: ARRAY [-N..N] OF INTEGER;
  c: SET OF CHR(0)..CHR(255);
BEGIN
  s := [1, 3]; t := [2]; c := ['a'];
  WRITELN(1 IN s, ' ', 2 IN s, ' ', 2 IN t, ' ', 'a' IN c, ' ', LOWER(s), ' ', UPPER(s));
  a[-3] := 5; b[-3] := 6;
  WRITELN(a[-3], ' ', b[-3], ' ', LOWER(a), ' ', UPPER(a), ' ', LOWER(b))
END.
