{ Baseline probe G12; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := 200; WRITELN(SQR(i))
END.
