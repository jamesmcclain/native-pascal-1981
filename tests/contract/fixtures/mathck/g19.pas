{ Baseline probe G19; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR i: INTEGER;
BEGIN
  FOR i := 32765 TO 32767 DO BEGIN END; WRITELN(3)
END.
