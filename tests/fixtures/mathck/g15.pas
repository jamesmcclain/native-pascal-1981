{ Baseline probe G15; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD;
BEGIN
  w := 40000; WRITELN(w MOD 7)
END.
