{ Baseline probe G6.integer.div; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b: INTEGER;
BEGIN
  a := 7; b := 0; WRITELN('prefix'); WRITELN(a DIV b)
END.
