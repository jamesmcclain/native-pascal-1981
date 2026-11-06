{ DIALECT: vintage extended }
{ A REAL literal above the largest double is a located lexer error. It used
  to become infinity, which the AST JSON spelled null, and the program then
  printed NaN. A literal below the smallest subnormal is still zero. }
PROGRAM real_literal_out_of_range_bad(OUTPUT);
BEGIN
  WRITELN(1.0E-400);
  WRITELN(1.7976931348623159E308)
END.
