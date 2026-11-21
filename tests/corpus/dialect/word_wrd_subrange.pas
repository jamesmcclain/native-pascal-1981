{ DIALECT: vintage extended }
{ NEW-37: WRD(0)..127, 0..WRD(127), and BYWORD(...) subranges have WORD as
  their host type (IBM manual 5-7), including in SET OF and ARRAY index bounds. }
PROGRAM WordWrdSubrange(OUTPUT);
TYPE
  WSub = WRD(0)..127;
  WSub2 = 0..WRD(127);
  WBy = BYWORD(0, 1)..BYWORD(0, 10);
  WSet = SET OF WSub;
  WSetInline = SET OF WRD(0)..127;
VAR
  a: WSub;
  b: WSub2;
  c: WBy;
  w: WORD;
  s1: WSet;
  s2: WSetInline;
  arr: ARRAY [WRD(0)..3] OF INTEGER;
BEGIN
  a := WRD(42);
  b := WRD(99);
  c := WRD(7);
  w := a;
  WRITELN(w);
  w := b;
  WRITELN(w);
  w := c;
  WRITELN(w);
  s1 := [1, 42, 100];
  s2 := [0, 7, 127];
  WRITELN(a IN s1);
  WRITELN(c IN s2);
  WRITELN(100 IN s1);
  w := LOWER(arr);
  WRITELN(w);
  w := UPPER(arr);
  WRITELN(w)
END.
