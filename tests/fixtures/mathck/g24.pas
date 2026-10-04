{ Baseline probe G24; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD; i: INTEGER;
BEGIN
  w := 40000; i := 1; w := w + i; WRITELN(w)
END.
