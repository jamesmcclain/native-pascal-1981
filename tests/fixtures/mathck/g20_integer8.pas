{ Baseline probe G20.integer8; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER8;
BEGIN
  i := 127; WRITELN(i + 1)
END.
