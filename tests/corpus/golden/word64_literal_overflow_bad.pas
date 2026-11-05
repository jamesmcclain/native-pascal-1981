{ DIALECT: extended }
{ 2^64 fits no integer type: a located lexer error, not a wrapped value or
  a crash in the compiler. }
PROGRAM word64_literal_overflow_bad(OUTPUT);
VAR w: WORD64;
BEGIN
  w := 18446744073709551616
END.
