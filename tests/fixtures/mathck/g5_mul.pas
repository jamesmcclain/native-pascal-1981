{ Baseline probe G5.mul; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD;
BEGIN
  w := 300; WRITELN(w * 300)
END.
