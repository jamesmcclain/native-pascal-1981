PROGRAM MathckMetadataConst(output);
{ Extended only: CONST intrinsic calls need extended-const-intrinsics. }
CONST
  C1 = SUCC(3);
  C2 = {$MATHCK-} PRED(3);
  {$MATHCK+}
  C3 = SUCC(C2);
VAR
  x: INTEGER;
BEGIN
  x := C1 + C2 + C3;
  WRITELN(x)
END.
