{ DIALECT: extended }
{ VSPLAT with a runtime scalar lowers to insertelement into undef at lane 0
  then a zero-mask shufflevector. A constant scalar folds to a splat
  constant instead (covered by the golden), so the RHS here is computed. }
{ CHECK: insertelement <4 x double> undef, double }
{ CHECK: shufflevector <4 x double> }
{ CHECK: <4 x i32> zeroinitializer }
PROGRAM VSplatShape(output);
TYPE V4D = VECTOR [4] OF REAL;
VAR a: V4D; x: REAL;
BEGIN
  x := 3.0;
  a := VSPLAT(x + 0.25, V4D);
  WRITELN(a[0]:0:2)
END.
