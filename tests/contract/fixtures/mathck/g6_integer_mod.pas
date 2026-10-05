{ Baseline probe G6.integer.mod; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b: INTEGER;
BEGIN
  a := 7; b := 0; WRITELN('prefix'); WRITELN(a MOD b)
END.
