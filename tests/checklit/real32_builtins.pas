{ DIALECT: extended }
{ The scalar builtins take a REAL32 argument at its own width. TRUNC,
  ROUND, FLOAT, and the libm calls widen it to double with fpext; ABS and
  SQR stay in float. None of them treats the float as an integer. }
{ CHECK: fpext float }
{ CHECK: fptosi double }
{ CHECK: fcmp olt float }
{ CHECK: fsub float }
{ CHECK: fmul float }
{ CHECK: call double @sqrt(double }
{ CHECK-NOT: sitofp float }
{ CHECK-NOT: icmp slt float }
{ CHECK-NOT: = mul float }
{ CHECK-NOT: = sub float }
PROGRAM Real32Builtins;
VAR
  a, b: REAL32;
  r: REAL;
  i: INTEGER;
BEGIN
  a := 2.75;
  i := TRUNC(a);
  i := ROUND(a);
  b := ABS(a);
  b := SQR(a);
  r := SQRT(a);
  r := FLOAT(a)
END.
