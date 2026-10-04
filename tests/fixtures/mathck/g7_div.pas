{ Baseline probe G7.div; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b: INTEGER;
BEGIN
  a := -32768; b := -1; WRITELN(a DIV b)
END.
