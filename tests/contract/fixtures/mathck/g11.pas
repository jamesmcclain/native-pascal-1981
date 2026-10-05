{ Baseline probe G11; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := -32768; WRITELN(ABS(i))
END.
