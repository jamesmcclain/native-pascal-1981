{ Baseline probe G23.add; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR k: INTEGER;
BEGIN
  k := 32767 + 1; WRITELN(k)
END.
