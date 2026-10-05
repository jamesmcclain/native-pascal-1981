{ DIALECT: extended }
{ A parameterless function named without an argument list is a valid
  LOWER/UPPER operand. Its bounds are its result type's, and the call is
  not executed (calls stays 0). }
PROGRAM BoundBareFunction(output);
TYPE BoolSet = SET OF BOOLEAN; Color = (red, green, blue); Arr = ARRAY['a'..'c'] OF INTEGER;
     Small = 3..9;
VAR bs: BoolSet; calls: INTEGER; f: BOOLEAN; c: CHAR; col: Color; i: INTEGER;
FUNCTION getb: BoolSet; BEGIN calls := calls + 1; getb := bs END;
FUNCTION getc: Color; BEGIN calls := calls + 1; getc := green END;
FUNCTION geta: Arr; VAR a: Arr; BEGIN calls := calls + 1; geta := a END;
FUNCTION gets: Small; BEGIN calls := calls + 1; gets := 4 END;
BEGIN
  calls := 0;
  WRITELN(LOWER(getb), ' ', UPPER(getb), ' ', UPPER(bs - getb));
  WRITELN(LOWER(getc), ' ', UPPER(getc), ' ', LOWER(geta), ' ', UPPER(geta));
  WRITELN(LOWER(gets), ' ', UPPER(gets), ' ', calls);
  f := UPPER(getb); c := UPPER(geta); col := LOWER(getc); i := UPPER(gets);
  WRITELN(f, ' ', c, ' ', col, ' ', i, ' ', calls);
END.
