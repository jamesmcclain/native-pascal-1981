{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ REAL unary minus is an IEEE negation: it flips the sign, so -0.0 is
  negative zero and -x of 0.0 is -0.0. It used to be 0.0 - x, which gives
  +0.0 for both, and CONST Z = -0.0 reached the program as +0.0. A zero's
  sign shows in 1.0 / z, which is -INF for -0.0 and +INF for +0.0. ABS of
  either zero is +0.0. A numeric CONST name may take a sign (IBM manual
  5-9): -Z negates a REAL CONST and -N an integer one. The other
  negations are unchanged. }
PROGRAM real_negative_zero(OUTPUT);
CONST
  Z = -0.0;
  P = 0.0;
  NZ = -Z;
  NP = -P;
  AZ = Z;
  PP = +P;
  R = 2.5;
  MR = -R;
  MMR = -MR;
  N = 5;
  MN = -N;
TYPE
  TN = -N .. N;
VAR
  x, y, w: REAL;
  a: ARRAY [MN .. N] OF INTEGER;
  b: ARRAY [-N .. N] OF INTEGER;
  t: TN;
  i: INTEGER;

FUNCTION Neg(v: REAL): BOOLEAN;
{ v is negative or negative zero. }
BEGIN
  IF v = 0.0 THEN Neg := 1.0 / v < 0.0 ELSE Neg := v < 0.0
END;

BEGIN
  { Literals and CONSTs }
  WRITELN('literal -0.0  ', Neg(-0.0), ' ', Neg(-(0.0)), ' ', Neg(0.0));
  WRITELN('CONST -0.0    ', Neg(Z), ' ', Neg(P), ' ', Neg(AZ), ' ', Neg(PP));
  WRITELN('CONST -name   ', Neg(NZ), ' ', Neg(NP));
  { Run time }
  x := 0.0;
  y := -x;
  w := -y;
  WRITELN('-x of 0.0     ', Neg(y), ' ', Neg(w), ' ', Neg(-Z), ' ', Neg(-NZ));
  WRITELN('ABS of zeros  ', Neg(ABS(Z)), ' ', Neg(ABS(y)), ' ', Neg(ABS(x)));
  WRITELN('zeros equal   ', y = x, ' ', Z = P, ' ', y < x);
  { Ordinary negation }
  x := 3.25;
  WRITELN(-x:6:2, -(-x):6:2, -R:6:2, MR:6:2, MMR:6:2, ABS(-x):6:2);
  WRITELN(-x + 1.0:6:2, 2.0 * (-x):7:2, -1.0E300 * 10.0 < -1.0E300);
  { Signed integer CONST names }
  t := -N;
  b[-N] := 7;
  WRITELN(MN:3, -N:3, LOWER(a):3, UPPER(a):3, LOWER(b):3, t:3, b[-5]:3);
  i := -5;
  CASE i OF
    -N: WRITELN('label -N');
    N: WRITELN('label N');
    OTHERWISE WRITELN('no label')
  END
END.
