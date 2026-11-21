{ DIALECT: vintage extended }
{ NEW-33: CHAR literals, variables and expressions convert automatically to
  length-1 LSTRINGs in variable, designator, function-result and value-parameter
  positions (IBM manual 6-18). }
PROGRAM LStringCharAssign(OUTPUT);
TYPE
  L10 = LSTRING(10);
  Rec = RECORD
    s: L10;
  END;
VAR
  l: L10;
  c: CHAR;
  r: Rec;
  a: ARRAY [1..2] OF L10;
  ca: ARRAY [1..2] OF CHAR;

FUNCTION MakeLit: L10;
BEGIN
  MakeLit := 'x'
END;

FUNCTION MakeVar(ch: CHAR): L10;
BEGIN
  MakeVar := ch
END;

FUNCTION MakeNested(ch: CHAR): L10;
  PROCEDURE SetIt;
  BEGIN
    MakeNested := ch
  END;
BEGIN
  SetIt
END;

PROCEDURE Show(s: L10);
BEGIN
  WRITELN(ORD(s.LEN), ':', s)
END;

BEGIN
  l := 'a';
  WRITELN(ORD(l.LEN), ':', l);
  c := 'B';
  l := c;
  WRITELN(ORD(l.LEN), ':', l);
  l := CHR(67);
  WRITELN(ORD(l.LEN), ':', l);
  l := MakeLit;
  WRITELN(ORD(l.LEN), ':', l);
  l := MakeVar('y');
  WRITELN(ORD(l.LEN), ':', l);
  l := MakeNested('z');
  WRITELN(ORD(l.LEN), ':', l);
  r.s := 'r';
  WRITELN(ORD(r.s.LEN), ':', r.s);
  a[1] := c;
  WRITELN(ORD(a[1].LEN), ':', a[1]);
  ca[1] := 'k';
  Show('q');
  Show(c);
  Show(ca[1]);
  Show(CHR(68))
END.
