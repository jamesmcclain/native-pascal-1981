{ Baseline probe G20.integer32; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER32;
BEGIN
  i := 2147483647; WRITELN(i + 1)
END.
