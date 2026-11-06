{ DIALECT: extended }
{ Index expressions of the index type's kind are accepted: any integer
  width for an integer index range, CHAR for a CHAR range, the array's
  own enumeration (or BOOLEAN) for a named ordinal index type. }
PROGRAM ixok(OUTPUT);
TYPE
  color = (red, green, blue);
VAR
  a: ARRAY [1..4] OF INTEGER;
  b: ARRAY [1..3] OF ARRAY ['a'..'c'] OF INTEGER;
  ca: ARRAY ['a'..'z'] OF INTEGER;
  ea: ARRAY [color] OF INTEGER;
  ba: ARRAY [BOOLEAN] OF INTEGER;
  i: INTEGER;
  w: WORD;
  l: INTEGER32;
  ch: CHAR;
  c: color;
BEGIN
  i := 1; w := 2; l := 3;
  a[i] := 10; a[w] := 20; a[l] := 30; a[4] := 40;
  ch := 'b';
  ca['a'] := 1; ca[ch] := 2;
  b[w]['c'] := 7; b[1][ch] := 8;
  FOR c := red TO blue DO ea[c] := ORD(c) * 100;
  ea[SUCC(red)] := ea[green] + 1;
  ba[FALSE] := 5; ba[i > 0] := 6;
  WRITELN(a[1], ' ', a[2], ' ', a[3], ' ', a[4]);
  WRITELN(ca['a'], ' ', ca['b'], ' ', b[2]['c'], ' ', b[1]['b']);
  WRITELN(ea[red], ' ', ea[green], ' ', ea[blue]);
  WRITELN(ba[FALSE], ' ', ba[TRUE])
END.
