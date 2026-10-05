{ Baseline probe G2; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i,k: INTEGER;
BEGIN
  i := -32767; k := i - 2; WRITELN(k)
END.
