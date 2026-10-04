{ Baseline probe G10.succ; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := 32767; WRITELN(SUCC(i))
END.
