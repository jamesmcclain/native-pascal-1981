{ DIALECT: vintage }
{ OPT: 0 1 2 3 }
PROGRAM encode_enum_vintage;
{ Vintage WRITE prints an enumerated value as its ordinal, so ENCODE does. }
TYPE color = (red, green, blue);
     warm = red..green;
VAR s: LSTRING(8); e: color; w: warm; b: BOOLEAN;
BEGIN
  e := green;
  IF ENCODE(s, e) THEN WRITELN('[', s, ']');
  IF ENCODE(s, e:4) THEN WRITELN('[', s, ']');
  IF ENCODE(s, blue) THEN WRITELN('[', s, ']');
  w := red;
  IF ENCODE(s, w) THEN WRITELN('[', s, ']');
  b := e = green;
  IF ENCODE(s, b) THEN WRITELN('[', s, ']');
END.
