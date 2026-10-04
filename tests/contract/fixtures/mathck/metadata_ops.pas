PROGRAM MathckMetadataOps(output);
PROCEDURE Run;
VAR
  a, b, x: INTEGER;
  r: REAL;
  s: SET OF 0..7;
  f: BOOLEAN;
BEGIN
  a := 1; b := 2;
  x := a + b - a * b DIV a MOD b;
  x := -a;
  x := a + {$MATHCK-} b;
  x := a {$MATHCK-} - b;
  {$MATHCK+}
  x := a {$MATHCK-} * a + {$MATHCK+} a MOD a;
  x := {$MATHCK-} -a * {$MATHCK+} a;
  {$MATHCK+}
  r := a / b;
  s := [1] + [2] - [1] * [2];
  f := (a < b) AND NOT (a = b) OR (a IN s);
  IF (a > 0) AND THEN (b > 0) OR ELSE (a <> b) THEN x := a;
  {$MATHCK:0}
  x := a + b;
  {$MATHCK:1}
  x := a + b;
  {$PUSH}{$MATHCK-}
  x := a + b;
  {$POP}
  x := a + b;
  {$DEBUG-}
  x := a + b;
  {$DEBUG+}
  x := a + b;
  {$DEBUG-}{$MATHCK+}
  x := a + b;
  {$DEBUG+}
  x := a + (b + a);
  x := a + (b {$MATHCK-} + a)
END;
BEGIN
  Run
END.
