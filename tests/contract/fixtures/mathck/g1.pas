{ Baseline probe G1; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i,k: INTEGER;
BEGIN
  i := 32767; k := i + 1; WRITELN(k)
END.
