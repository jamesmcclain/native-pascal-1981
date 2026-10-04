{ DIALECT: extended }
PROGRAM const_shadow_coerce(OUTPUT);
{ A variable that shadows a CONST must not fold to the CONST's value when
  an INTEGER operand is widened for assignment or for mixed-width
  arithmetic. Regression guard for a review finding: both lines printed
  40000-based values. }
CONST big = 40000;
PROCEDURE p;
VAR big: INTEGER; x: INTEGER32;
BEGIN
  big := 5;
  x := big;
  WRITELN(x);
  x := x + big;
  WRITELN(x)
END;
BEGIN
  p
END.
