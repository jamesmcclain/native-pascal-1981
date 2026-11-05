{ DIALECT: extended }
{ An upper-half WORD64 literal is out of range for every other integer
  type, and below -2^63 a negated literal fits nothing. }
PROGRAM word64_literal_range_rejected(OUTPUT);
CONST NEG = -9223372036854775809;
VAR i: INTEGER64; d: WORD32;
BEGIN
  i := 9223372036854775808;
  d := 18446744073709551615;
  i := -18446744073709551615
END.
