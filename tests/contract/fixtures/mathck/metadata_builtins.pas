PROGRAM MathckMetadataBuiltins(output);
PROCEDURE Run;
VAR
  a, b, x: INTEGER;
  w: WORD;
  c: CHAR;
  r: REAL;
BEGIN
  a := 1; b := 2; w := 3; r := 1.5;
  x := SUCC(a) + PRED(b);
  x := ABS(a) * SQR(b);
  w := SUCC(w);
  x := succ(a) + Abs(b);
  x := ABS({$MATHCK-} a + b);
  x := {$MATHCK-} SQR({$MATHCK+} a - b);
  {$MATHCK+}
  x := SUCC(PRED({$MATHCK-} a));
  {$MATHCK+}
  x := ORD(CHR(a)) + TRUNC(r);
  c := SUCC('a');
  r := ABS(r) + SQR(r);
  CASE a OF
    SUCC(0): x := 0;
    {$MATHCK-} PRED(5): x := 1
  END;
  {$MATHCK+}
  x := -SQR(a)
END;
BEGIN
  Run
END.
