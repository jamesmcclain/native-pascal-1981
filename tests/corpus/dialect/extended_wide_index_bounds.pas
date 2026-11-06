{ DIALECT: extended }
{ NEW-5: an integer array index takes the narrowest of INTEGER, WORD and
  INTEGER32 that holds its upper bound, however the bound is spelled, and
  LOWER/UPPER return the bound at that width. UPPER of ARRAY [0..70000]
  printed 4464 (70000 truncated to 16 bits), and -5..70000 silently became
  65531..70000. A SUPER ARRAY's bounds stay INTEGER64. }
PROGRAM ExtendedWideIndexBounds(OUTPUT);
CONST
  N = 70000;
  M = 40000;
TYPE
  S = SUPER ARRAY [40000..*] OF CHAR;
VAR
  a: ARRAY [0..70000] OF CHAR;
  b: ARRAY [-5..70000] OF CHAR;
  c: ARRAY [0..N] OF CHAR;
  d: ARRAY [M..N] OF CHAR;
  e: ARRAY [1..SUCC(N)] OF CHAR;
  w: ARRAY [0..M] OF CHAR;
  p: ^S;
  x: INTEGER32;
  q: INTEGER64;
BEGIN
  WRITELN(LOWER(a), ' ', UPPER(a));
  WRITELN(LOWER(b), ' ', UPPER(b));
  WRITELN(LOWER(c), ' ', UPPER(c));
  WRITELN(LOWER(d), ' ', UPPER(d));
  WRITELN(LOWER(e), ' ', UPPER(e));
  WRITELN(LOWER(w), ' ', UPPER(w));
  x := UPPER(a) + 1;
  WRITELN(x);
  x := 0;
  FOR x := UPPER(a) - 2 TO UPPER(a) DO a[x] := 'z';
  WRITELN(a[69999], a[70000]);
  x := LOWER(b);
  b[x] := 'm';
  x := UPPER(b);
  b[x] := 'n';
  WRITELN(b[-5], b[70000]);
  NEW(p, 40003);
  q := UPPER(p^);
  WRITELN(LOWER(p^), ' ', q);
  DISPOSE(p)
END.
