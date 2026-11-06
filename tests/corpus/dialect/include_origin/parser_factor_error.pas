{ A parser error of several lines in an included file puts the location
  on its last line, the token the parser found. }
PROGRAM parser_factor_error(OUTPUT);
(*$INCLUDE:'parser_factor_error.inc'*)
BEGIN
  Fill;
  WRITELN(n)
END.
