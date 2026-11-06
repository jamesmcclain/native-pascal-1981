{ DIALECT: vintage }
{ A constant that does not fit the target is still rejected, and every
  intermediate value must fit 16 bits. }
PROGRAM constbad(OUTPUT);
VAR i: INTEGER;
BEGIN
  i := 0 - 32769;
  i := 32767 + 1;
  i := 40000 + 0;
  i := 0 - 32768 * 2 DIV 2
END.
