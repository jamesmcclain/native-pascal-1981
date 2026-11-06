{ DIALECT: vintage extended }
{ NEW-5: an index range whose upper bound is above 32767 is a WORD index
  however its bounds are spelled. The typechecker used to read only a
  literal high bound and codegen only a literal low one, so UPPER of
  ARRAY [Z..40000] printed -25536 and UPPER of ARRAY [0..HI] was typed
  INTEGER. Bounds within INTEGER keep INTEGER. }
PROGRAM VintageWordIndexBounds(OUTPUT);
CONST
  Z = 0;
  HI = 40000;
VAR
  g: ARRAY [Z..40000] OF CHAR;
  h: ARRAY [0..HI] OF CHAR;
  k: ARRAY [-3..32767] OF CHAR;
  m: ARRAY [40000..65535] OF CHAR;
  w: WORD;
  i: INTEGER;
BEGIN
  WRITELN(LOWER(g), ' ', UPPER(g));
  WRITELN(LOWER(h), ' ', UPPER(h));
  WRITELN(LOWER(k), ' ', UPPER(k));
  WRITELN(LOWER(m), ' ', UPPER(m));
  w := UPPER(g);
  WRITELN(w);
  w := UPPER(h);
  WRITELN(w);
  i := LOWER(k);
  WRITELN(i);
  w := UPPER(m);
  WRITELN(w)
END.
