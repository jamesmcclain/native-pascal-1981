{ Baseline probe G26.round; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := ROUND(100000.0); WRITELN(i)
END.
