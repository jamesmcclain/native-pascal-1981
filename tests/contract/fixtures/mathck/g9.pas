{ Baseline probe G9; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR k: INTEGER;
BEGIN
  k := 7 DIV 0; WRITELN(k)
END.
