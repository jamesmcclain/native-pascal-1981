{ DIALECT: vintage extended }
PROGRAM write_char_array(OUTPUT);
{ WRITE of a one-dimensional ARRAY OF CHAR writes all of its components,
  like a STRING(n) of the same length, at any lower bound: a whole
  variable, a record field, an array row, a VAR formal and a function
  result, with and without a field width. }
TYPE Pair = ARRAY [1..2] OF CHAR;
     Low = 'a'..'z';
     Rec = RECORD tag: ARRAY [0..2] OF CHAR; n: INTEGER END;
VAR a: Pair;
    z: ARRAY [-1..1] OF CHAR;
    s: ARRAY [5..7] OF Low;
    r: Rec;
    m: ARRAY [1..2] OF Pair;
    calls, k: INTEGER;
PROCEDURE Show(VAR p: Pair);
BEGIN WRITELN('<', p, '>', p:3) END;
FUNCTION MakePair(c: CHAR): Pair;
VAR t: Pair;
BEGIN calls := calls + 1; t[1] := c; t[2] := c; MakePair := t END;
BEGIN
  calls := 0;
  a[1] := 'h'; a[2] := 'i';
  WRITELN(a); WRITELN(a:4, '|'); WRITELN(a:-4, '|');
  z[-1] := 'x'; z[0] := 'y'; z[1] := 'z';
  WRITELN(z, '|', z:5, '|');
  s[5] := 'a'; s[6] := 'b'; s[7] := 'c';
  WRITELN(s);
  r.tag[0] := 'T'; r.tag[1] := 'A'; r.tag[2] := 'G'; r.n := 7;
  WRITELN(r.tag, r.n:2);
  m[1] := a; m[2][1] := 'o'; m[2][2] := 'k';
  FOR k := 1 TO 2 DO WRITE(m[k], ' ');
  WRITELN;
  Show(a);
  WRITELN(MakePair('q'), MakePair('w'):4);
  WRITELN('calls=', calls:1)
END.
