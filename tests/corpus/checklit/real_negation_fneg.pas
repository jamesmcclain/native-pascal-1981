{ DIALECT: extended }
{ OPT: 0 2 }
{ REAL and REAL32 unary minus is an IEEE negation (fneg), not 0.0 - x:
  fsub from +0.0 loses the sign of a zero, so -x of 0.0 was +0.0. }
{ CHECK: fneg double }
{ CHECK: fneg float }
{ CHECK-NOT: fsub }
PROGRAM RealNegationFneg;
VAR
  a: REAL32;
  r: REAL;

FUNCTION NegR(x: REAL): REAL;
BEGIN
  NegR := -x
END;

FUNCTION NegF(x: REAL32): REAL32;
BEGIN
  NegF := -x
END;

BEGIN
  r := NegR(0.0);
  a := NegF(a)
END.
