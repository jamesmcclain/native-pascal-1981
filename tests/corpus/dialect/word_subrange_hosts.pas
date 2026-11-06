{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-32: an integer subrange's host is the narrowest of INTEGER, WORD and
  INTEGER32 that holds its upper bound, the NEW-5 array index rule, in
  the typechecker as in codegen. The IBM manual (5-7) makes 0..50000 a
  WORD subrange. The typechecker used to give every integer subrange the
  host INTEGER, so `b := 40000' for 0..40000 was rejected ("Positive
  integer constant out of range for INTEGER"), and codegen stopped at any
  bound above 32767. Covers the 32767/32768 and 65535 edges, a CONST
  bound, stores, WRITE (unsigned, with a width), comparisons,
  arithmetic, value and VAR parameters, a function result, a record
  field, an array indexed by the subrange type, FOR in both directions
  and CASE. }
PROGRAM WordSubrangeHosts(OUTPUT);
CONST
  HI = 40000;
TYPE
  Big = 0..HI;
  Top = 32768..65535;
  Edge = 0..32767;
  Edge2 = 0..32768;
  Full = 0..65535;
  Rec = RECORD f: Big; g: Top END;
VAR
  b: Big;
  lit: 0..40000;
  t: Top;
  e: Edge;
  e2: Edge2;
  f: Full;
  w: WORD;
  i: INTEGER;
  r: Rec;
  a: ARRAY [Big] OF CHAR;
  k: Top;
  n: INTEGER;

PROCEDURE ShowB(x: Big);
BEGIN
  WRITELN('val ', x)
END;

PROCEDURE IncB(VAR x: Big);
BEGIN
  x := x + 1
END;

FUNCTION Twice(x: Big): Top;
BEGIN
  Twice := x * 2
END;

BEGIN
  lit := 40000;
  WRITELN(lit);
  b := 40000;
  WRITELN(b);
  WRITELN(b:8, '|');
  t := 65535;
  WRITELN(t, ' ', t DIV 2, ' ', t - 1);
  e := 32767;
  e2 := 32768;
  f := 65535;
  WRITELN(e, ' ', e2, ' ', f);
  i := e;
  w := e2;
  WRITELN(i, ' ', w);
  WRITELN(LOWER(e), ' ', UPPER(e), ' ', UPPER(e2), ' ', UPPER(t), ' ',
          UPPER(f));
  w := UPPER(b);
  WRITELN(w);
  w := b;
  b := w;
  WRITELN(w, ' ', b);
  b := 39999;
  IF b < 40000 THEN WRITELN('lt');
  IF b > 32767 THEN WRITELN('gt');
  IF t = 65535 THEN WRITELN('eq');
  b := b + 1;
  WRITELN(b);
  ShowB(b);
  b := 39999;
  IncB(b);
  WRITELN(b);
  WRITELN(Twice(20000));
  r.f := 40000;
  r.g := 40001;
  WRITELN(r.f, ' ', r.g);
  a[40000] := 'z';
  a[0] := 'a';
  WRITELN(a[0], a[40000], ' ', UPPER(a));
  n := 0;
  FOR k := 65530 TO 65535 DO n := n + 1;
  WRITELN(n);
  n := 0;
  FOR b := 39998 TO UPPER(b) DO n := n + 1;
  WRITELN(n);
  FOR k := 65535 DOWNTO 65533 DO WRITE(k, ' ');
  WRITELN;
  t := 50000;
  CASE t OF
    32768: WRITELN('low');
    50000: WRITELN('fifty');
    65535: WRITELN('high')
  END
END.
