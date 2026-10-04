PROGRAM benchwide(input, output);
{ MATHCK overhead workload (tests/optional/mathck_overhead.py), extended dialect:
  20 million INTEGER32 multiply-accumulates (|a| <= 1000, so each row sum
  stays below 1.1e9) folded into an INTEGER64 total. }
{$MATHCK+}
PROCEDURE probe;
VAR a: ARRAY [0..1023] OF INTEGER32; i, j, seed: INTEGER32;
    k: INTEGER32; s: INTEGER64;
BEGIN
  READLN(seed);
  FOR i := 0 TO 1023 DO a[i] := (i * seed) MOD 2001 - 1000;
  s := 0;
  FOR j := 1 TO 20000 DO
  BEGIN
    { Negate one element so every row differs (no loop-invariant sum). }
    a[j MOD 1023 + 1] := -a[j MOD 1023 + 1];
    k := j;
    FOR i := 1 TO 1023 DO k := k + a[i] * a[i - 1];
    s := s + k
  END;
  WRITELN(s)
END;
BEGIN probe END.
