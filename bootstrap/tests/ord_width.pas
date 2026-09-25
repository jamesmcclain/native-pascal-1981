{ ORD gives what the native compiler gives: a CHAR zero-extends to a 16-bit
  INTEGER, an integer keeps its own value and width, and an enumeration's
  ordinal is an INTEGER32. }
(*$INCLUDE:'testio.inc'*)
PROGRAM ord_width(input, output);
USES testio;

TYPE
  Color = (red, green, blue);

VAR
  i, j: INTEGER;
  l, k: INTEGER32;
  c: Color;

BEGIN
  i := -1;
  j := ORD(i);
  WriteLabel('ORD(-1)');
  WriteInt(j);
  WRITELN;
  WriteLabel('ORD(CHR(200)) * 256');
  WriteInt(ORD(CHR(200)) * 256);
  WRITELN;
  WriteLabel('ORD(-1) < 0');
  WriteBool(ORD(i) < 0);
  WRITELN;
  WriteLabel('ORD(''A'') * 1000');
  WriteInt(ORD('A') * 1000);
  WRITELN;
  i := 32767;
  k := ORD(i) + 1;
  WriteLabel('ORD(32767) + 1');
  WriteInt(k);
  WRITELN;
  l := 100000;
  k := ORD(l);
  WriteLabel('ORD of INTEGER32 100000');
  WriteInt(k);
  WRITELN;
  c := blue;
  k := ORD(c);
  WriteLabel('ORD(blue)');
  WriteInt(k);
  WRITELN;
END.
