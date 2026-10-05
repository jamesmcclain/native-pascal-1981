{$MATHCK+}
PROGRAM OkDesignators;
TYPE R = RECORD f: INTEGER; g: WORD END;
VAR r: R; a: ARRAY [1..3] OF INTEGER; i: INTEGER;
BEGIN
  i := 2; a[i] := 30000;
  WRITELN(SADDOK(a[i], a[i], a[i + 1]), ' ', a[3]);
  WRITELN(UMULOK(WRD(i) * 300, 300, r.g), ' ', r.g);
  WRITELN(SMULOK(-i, 16384, r.f), ' ', r.f);
END.
