{ DIALECT: vintage extended }
{ A REAL literal's integer part may exceed every integer type. The lexer
  accumulated it in a MATHCK-checked INTEGER64 first, so a digit run past
  2^63 crashed the compiler before the '.' was seen. }
PROGRAM real_literal_wide_integer_part(OUTPUT);
BEGIN
  WRITELN(12345678901234567890123.5:26:1);
  WRITELN(99999999999999999999.0)
END.
