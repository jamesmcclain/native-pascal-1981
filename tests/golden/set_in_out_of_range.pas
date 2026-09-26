PROGRAM SetInOutOfRange(OUTPUT);
{ The IBM manual (8-9): X can be outside the range of the set's base type,
  and X IN B is then FALSE. Ordinals outside 0..255 must not index past
  the 256-bit set. }
VAR
  s: SET OF 0..9;
  t: SET OF 2..9;
  full: SET OF 0..255;
  i: INTEGER;
BEGIN
  s := [0, 1, 9];
  t := [2..9];
  full := [0..255];
  WRITELN('manual ', 1 IN t);
  i := -1;
  WRITELN('var -1 ', i IN s, ' ', i IN full);
  WRITELN('lit -1 ', -1 IN s);
  i := -32767;
  i := i - 1;
  WRITELN('var -32768 ', i IN full);
  i := 256;
  WRITELN('var 256 ', i IN full);
  i := 300;
  WRITELN('var 300 ', i IN s, ' ', i IN full);
  WRITELN('lit 300 ', 300 IN s);
  i := 32767;
  WRITELN('var 32767 ', i IN full);
  i := 0;
  WRITELN('edge 0 ', i IN s, ' ', i IN full);
  i := 255;
  WRITELN('edge 255 ', i IN s, ' ', i IN full);
  i := 9;
  WRITELN('in range ', i IN s, ' ', (i - 1) IN s)
END.
