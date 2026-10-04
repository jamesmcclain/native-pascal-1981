{ Baseline probe G22; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
CONST N = -65537;
VAR k: INTEGER;
BEGIN
  k := N DIV 2; WRITELN(k)
END.
