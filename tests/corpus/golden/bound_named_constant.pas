{ A named INTEGER or CHAR constant as the low bound of a subrange or an
  array index range gives the type of that constant's value. }
PROGRAM BoundNamedConstant(OUTPUT);
CONST
  lo = 1;
  first = 'a';
  second = 'b';
VAR
  x: lo..10;
  a: ARRAY[first..'z'] OF INTEGER;
  y: second..'y';
  ch: CHAR;
BEGIN
  x := 4;
  WRITELN(x + 1, LOWER(x), UPPER(x));
  ch := UPPER(a);
  WRITELN(ch, LOWER(a));
  y := 'q';
  WRITELN(y, LOWER(y), UPPER(y), y < 'r')
END.
