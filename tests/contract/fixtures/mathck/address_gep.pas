{ MATHCK+ at -S -O0: p + n and p + (n - 1) are two non-inbounds GEPs;
  only the offset's - is checked. The suite also swaps the last
  statement for each rejected pointer operator. }
{$MATHCK+}
PROGRAM Gep(output);
TYPE PI = ^INTEGER;
VAR p, q: PI; n: INTEGER32;
BEGIN
  NEW(p); n := 2147483647;
  q := p + n;
  q := p + (n - 1)
END.
