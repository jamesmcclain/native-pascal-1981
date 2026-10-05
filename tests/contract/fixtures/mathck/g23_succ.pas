{ Baseline probe G23.succ; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR k: INTEGER;
BEGIN
  k := SUCC(32767); WRITELN(k)
END.
