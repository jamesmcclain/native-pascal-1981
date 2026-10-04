{ Baseline probe G6.word.mod; see tests/mathck_baseline.json. }
{$MATHCK+}
PROGRAM MathProbe(input, output);
VAR a,b: WORD;
BEGIN
  a := 7; b := 0; WRITELN('prefix'); WRITELN(a MOD b)
END.
