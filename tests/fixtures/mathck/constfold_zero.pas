{ A constant zero divisor is a compile-time error under either setting,
  with a constant or a variable dividend, whether the zero is a literal,
  a CONST name or folded arithmetic. Expected: constfold_zero.err, and no
  output file. }
PROGRAM Bad; CONST Z = 0; VAR a: INTEGER;
BEGIN a := 7; WRITELN({EXPRESSION}) END.
