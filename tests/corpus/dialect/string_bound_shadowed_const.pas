{ DIALECT: vintage extended }
{ NEW-24r: UPPER and LOWER of a STRING(n) or LSTRING(n) use the capacity
  resolved at the string type's declaration site, even when an inner
  scope shadows the CONST name used as its capacity with another CONST of
  different width or with a variable. }
PROGRAM StringBoundShadowedConst(OUTPUT);
CONST
  SMALL = 10;
  BIG = 40000;
TYPE
  SmallAlias = STRING(SMALL);
  BigAlias = LSTRING(BIG);
  Rec = RECORD
    s: STRING(SMALL);
    b: LSTRING(BIG)
  END;
VAR
  vs: STRING(SMALL);
  vb: LSTRING(BIG);
  va: SmallAlias;
  vba: BigAlias;
  r: Rec;
  arr: ARRAY [1..2] OF STRING(SMALL);

FUNCTION MakeSmall: SmallAlias;
BEGIN
  MakeSmall := '0123456789'
END;

PROCEDURE ShadowWithBig;
CONST
  SMALL = 40000;
VAR
  BIG: INTEGER;
  i: INTEGER;
  w: WORD;
BEGIN
  BIG := 5;
  i := UPPER(vs);
  WRITELN('small var ', i, ' ', LOWER(vs));
  i := UPPER(va);
  WRITELN('small alias ', i);
  i := UPPER(r.s);
  WRITELN('small field ', i);
  i := UPPER(arr[1]);
  WRITELN('small elem ', i);
  i := UPPER(MakeSmall);
  WRITELN('small func ', i);
  w := UPPER(vb);
  WRITELN('big var ', w, ' ', LOWER(vb));
  w := UPPER(vba);
  WRITELN('big alias ', w);
  w := UPPER(r.b);
  WRITELN('big field ', w)
END;

BEGIN
  ShadowWithBig
END.
