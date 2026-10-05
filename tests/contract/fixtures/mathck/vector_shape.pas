{$MATHCK+}
{ Whole-vector check shape for tests/contract/mathck_optimization.sh; the suite
  replaces {ELEM} with INTEGER8, INTEGER, WORD32 and INTEGER64. }
PROGRAM vshape;
TYPE V = VECTOR [4] OF {ELEM};
VAR a, b, c: V;
BEGIN
  a := VSPLAT(1, V); b := VSPLAT(1, V);
  c := a + b; c := a - b; c := a * b; c := -a
END.
