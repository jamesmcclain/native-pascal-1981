{ Baseline probe G3; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i,k: INTEGER;
BEGIN
  i := 200; k := i * 200; WRITELN(k)
END.
