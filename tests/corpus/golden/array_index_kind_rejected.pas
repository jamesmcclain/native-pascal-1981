{ DIALECT: vintage }
{ An index expression must be assignment compatible with the array's
  index type (manual, Indexed Variables and Values). A CHAR, BOOLEAN or
  enumeration index of the wrong kind is a located typecheck error, for
  top-level, inner and SUPER arrays alike, as is a value of another
  enumeration. }
PROGRAM ixbad(OUTPUT);
TYPE
  color = (red, green, blue);
  shape = (square, circle);
  Data = SUPER ARRAY [1..*] OF INTEGER;
VAR
  a: ARRAY [1..4] OF INTEGER;
  b: ARRAY [1..3] OF ARRAY [1..4] OF INTEGER;
  ca: ARRAY ['a'..'z'] OF INTEGER;
  ea: ARRAY [color] OF INTEGER;
  ba: ARRAY [BOOLEAN] OF INTEGER;
  s: shape;
  p: ^Data;
  i: INTEGER;
BEGIN
  a['x'] := 0;
  b[1]['x'] := 0;
  a[TRUE] := 0;
  a[red] := 0;
  ca[1] := 0;
  ea[2] := 0;
  ea[square] := 0;
  ea[s] := 0;
  ba['y'] := 0;
  ba[i] := 0;
  b[red][1] := 0;
  p^['z'] := 0
END.
