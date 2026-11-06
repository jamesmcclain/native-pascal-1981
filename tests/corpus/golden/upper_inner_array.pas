{ DIALECT: vintage }
{ UPPER and LOWER of an array element that is itself an array have the
  inner index type: subrange, CHAR, named array and enumeration. }
PROGRAM up(OUTPUT);
TYPE color = (red, green, blue);
  row = ARRAY ['a'..'e'] OF INTEGER;
  crow = ARRAY [color] OF INTEGER;
VAR a: ARRAY [1..3] OF row;
  b: ARRAY [1..2] OF ARRAY [5..9] OF CHAR;
  c: ARRAY [1..2] OF crow;
  ch: CHAR; i: INTEGER; k: color;
BEGIN
  ch := UPPER(a[1]); WRITE(ch, ' ');
  ch := LOWER(a[2]); WRITE(ch, ' ');
  i := UPPER(b[1]); WRITE(i, ' ');
  k := UPPER(c[1]); WRITELN(ORD(k));
  a[1]['c'] := 7; WRITELN(a[1]['c'])
END.
