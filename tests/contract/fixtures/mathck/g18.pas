{ Baseline probe G18; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR w: WORD; n: INTEGER;
BEGIN
  n := 0; FOR w := 32766 TO 32770 DO n := n + 1; WRITELN(n)
END.
