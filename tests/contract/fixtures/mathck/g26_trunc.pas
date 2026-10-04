{ Baseline probe G26.trunc; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := TRUNC(100000.0); WRITELN(i)
END.
