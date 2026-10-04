{ Baseline probe G13.umulok; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b,c: WORD;
BEGIN
  a := 1; b := 2; WRITELN(UMULOK(a,b,c)); WRITELN(c)
END.
