{ DIALECT: vintage extended }
{ NEW-24: LOWER and UPPER of a STRING(n) or LSTRING(n) have the narrowest
  of INTEGER, WORD and INTEGER32 that holds the capacity n, as an array
  index range does (NEW-5), however the string is reached: a variable, a
  named type, a record field, an array element, a pointer target or a
  function result. Both were INTEGER, so UPPER of an LSTRING(40000)
  printed -25536. Capacities up to 32767 stay INTEGER. }
PROGRAM StringBoundTypes(OUTPUT);
CONST
  CAP = 40000;
TYPE
  Big = LSTRING(40000);
  Rec = RECORD
    f: Big;
    g: STRING(50000)
  END;
  PRec = ^Rec;
VAR
  l: Big;
  c: LSTRING(CAP);
  s: STRING(32768);
  m: LSTRING(32767);
  t: STRING(5);
  r: Rec;
  a: ARRAY [1..2] OF Big;
  p: PRec;
  w: WORD;
  i: INTEGER;

FUNCTION F: Big;
BEGIN
  F := 'xy'
END;

FUNCTION G(k: INTEGER): Big;
BEGIN
  G := 'xy'
END;

BEGIN
  NEW(p);
  WRITELN('variable ', LOWER(l), ' ', UPPER(l));
  WRITELN('const capacity ', UPPER(c));
  WRITELN('fixed ', LOWER(s), ' ', UPPER(s));
  WRITELN('field ', UPPER(r.f), ' ', LOWER(r.g), ' ', UPPER(r.g));
  WRITELN('element ', UPPER(a[1]));
  WRITELN('pointer ', UPPER(p^.f));
  WRITELN('function ', UPPER(F), ' ', UPPER(G(1)));
  w := UPPER(l);
  WRITELN('word ', w);
  w := UPPER(r.g);
  WRITELN('word ', w);
  w := LOWER(s);
  WRITELN('word ', w);
  i := UPPER(m);
  WRITELN('integer ', i, ' ', LOWER(m));
  i := UPPER(t);
  WRITELN('integer ', i, ' ', LOWER(t));
  DISPOSE(p)
END.
