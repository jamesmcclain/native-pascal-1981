{ Baseline probe G10.pred; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := -32768; WRITELN(PRED(i))
END.
