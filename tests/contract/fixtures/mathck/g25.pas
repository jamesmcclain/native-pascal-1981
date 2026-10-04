{ Baseline probe G25; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD; i: INTEGER;
BEGIN
  w := 40000; i := ORD(w); WRITELN(i)
END.
