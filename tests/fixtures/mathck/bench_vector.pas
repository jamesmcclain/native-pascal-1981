PROGRAM benchvector(input, output);
{ MATHCK overhead workload (tests/mathck_overhead.py), extended dialect:
  20 million steps of an 8-lane INTEGER32 recurrence p := p + q * c;
  q := q - p, with c = 1 read at run time. It has period 6, so the lanes stay
  bounded. MATHCK+ uses a whole-vector overflow check with a cold
  lane-by-lane failure path; MATHCK- keeps SIMD arithmetic. }
{$MATHCK+}
TYPE V = VECTOR [8] OF INTEGER32;
PROCEDURE probe;
VAR p, q, c: V; j, seed, lane: INTEGER32;
BEGIN
  READLN(seed);
  c := VSPLAT(seed, V);
  FOR lane := 0 TO 7 DO BEGIN p[lane] := lane * 100 - 350; q[lane] := 7 - lane END;
  FOR j := 1 TO 20000000 DO
  BEGIN
    p := p + q * c;
    q := q - p
  END;
  WRITELN(VSUM(p), ' ', VSUM(q))
END;
BEGIN probe END.
