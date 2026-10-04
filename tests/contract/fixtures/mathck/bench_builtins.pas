PROGRAM benchbuiltins(input, output);
{ MATHCK overhead workload (tests/optional/mathck_overhead.py): 20 million
  iterations of SQR, ABS and PRED; the sums telescope, so k stays small. }
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
    k := j MOD 5;
    FOR i := 1 TO 1023 DO
      k := k + SQR(a[i]) - SQR(a[PRED(i)]) + ABS(a[i]) - ABS(a[PRED(i)]);
    s := (s + k) MOD 10007
  END;
  WRITELN(s)
END;
BEGIN probe END.
