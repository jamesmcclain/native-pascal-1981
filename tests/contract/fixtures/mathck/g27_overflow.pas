{ Baseline probe G27.overflow; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR r: REAL;
BEGIN
  r := 1.0E308; r := r * 10.0; WRITELN(r); WRITELN(-r)
END.
