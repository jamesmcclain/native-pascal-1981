{ Baseline probe G20.integer64; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER64;
BEGIN
  i := 9223372036854775807; WRITELN(i + 1)
END.
