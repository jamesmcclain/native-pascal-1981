{ Baseline probe G13.saddok; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b,c: INTEGER;
BEGIN
  a := 1; b := 2; WRITELN(SADDOK(a,b,c)); WRITELN(c)
END.
