{ DIALECT: extended }
{ Scalar builtins on REAL32 arguments, and on integers wider or narrower
  than INTEGER. ABS and SQR keep the argument's type, so their results
  stay REAL32 or INTEGER32 in the expressions around them. }
PROGRAM Real32Builtins(OUTPUT);
VAR
  a, b: REAL32;
  r: REAL;
  l: INTEGER32;
  s: INTEGER8;
BEGIN
  a := 2.75;
  b := -2.75;
  WRITELN('TRUNC ', TRUNC(a), ' ', TRUNC(b));
  WRITELN('ROUND ', ROUND(a), ' ', ROUND(b));
  a := 2.5;
  b := -2.5;
  WRITELN('ROUND half ', ROUND(a), ' ', ROUND(b));
  a := 0.25;
  WRITELN('TRUNC small ', TRUNC(a), ' ', ROUND(a));
  b := -1.5;
  a := ABS(b);
  WRITELN('ABS ', TRUNC(a * 10.0), ' ', TRUNC(ABS(b) + 0.5));
  a := SQR(b);
  WRITELN('SQR ', TRUNC(a * 100.0), ' ', TRUNC(SQR(b) - 0.25));
  a := 6.25;
  r := SQRT(a);
  WRITELN('SQRT ', TRUNC(r * 10.0));
  WRITELN('FLOAT ', TRUNC(FLOAT(a) * 4.0));
  a := 0.0;
  WRITELN('EXP ', ROUND(EXP(a)), ' SIN ', ROUND(SIN(a)), ' COS ', ROUND(COS(a)));
  l := -70000;
  WRITELN('ABS32 ', ABS(l), ' SQR32 ', SQR(l DIV 1000));
  s := -5;
  WRITELN('ABS8 ', ORD(ABS(s)))
END.
