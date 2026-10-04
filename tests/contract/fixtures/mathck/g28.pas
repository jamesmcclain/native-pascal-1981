{ Baseline probe G28; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  i := -7; WRITELN(i DIV 2); WRITELN(i MOD 2)
END.
