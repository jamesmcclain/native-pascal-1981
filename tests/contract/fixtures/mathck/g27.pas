{ Baseline probe G27; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR x: REAL;
BEGIN
  x := 1.0; WRITELN(x / 0.0)
END.
