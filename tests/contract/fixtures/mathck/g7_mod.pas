{ Baseline probe G7.mod; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b: INTEGER;
BEGIN
  a := -32768; b := -1; WRITELN(a MOD b)
END.
