{ Baseline probe G5.add; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD;
BEGIN
  w := 65535; WRITELN(w + 1)
END.
