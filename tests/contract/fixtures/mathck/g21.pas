{ Baseline probe G21; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD32;
BEGIN
  w := 4000000000; WRITELN(w DIV 2); WRITELN(w > 2)
END.
