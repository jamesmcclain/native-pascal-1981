{ DIALECT: extended }
{ OPT: 0 2 }
{ REAL32 unary minus is an IEEE negation too: -x of 0.0 is -0.0, and ABS
  of -0.0 is +0.0 (see real_negative_zero for REAL). }
PROGRAM real32_negative_zero(OUTPUT);
VAR
  x, y, w: REAL32;
  one: REAL32;
BEGIN
  one := 1.0;
  x := 0.0;
  y := -x;
  w := -y;
  WRITELN(one / y < 0.0, ' ', one / w < 0.0, ' ', one / ABS(y) < 0.0);
  x := 1.5;
  WRITELN(-x:6:2, -(-x):6:2, ABS(-x):6:2)
END.
