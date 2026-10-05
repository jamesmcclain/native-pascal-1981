PROGRAM benchscalar(input, output);
{ MATHCK overhead workload (tests/optional/mathck_overhead.py): 20 million 16-bit
  iterations of k := k + a[i] * 2 - a[i - 1] over data from the seed;
  |a| <= 10 keeps every partial sum inside INTEGER. }
{$MATHCK+}
PROCEDURE probe;
VAR a: ARRAY [0..1023] OF INTEGER; i, j, k, s, seed: INTEGER;
BEGIN
  READLN(seed);
  FOR i := 0 TO 1023 DO a[i] := (i * seed) MOD 21 - 10;
  s := 0;
  FOR j := 1 TO 20000 DO
  BEGIN
    { Negate one element so every row differs (no loop-invariant sum). }
    a[j MOD 1023 + 1] := -a[j MOD 1023 + 1];
    k := j MOD 3;
    FOR i := 1 TO 1023 DO k := k + a[i] * 2 - a[i - 1];
    s := (s + k) MOD 10007
  END;
  WRITELN(s)
END;
BEGIN probe END.
