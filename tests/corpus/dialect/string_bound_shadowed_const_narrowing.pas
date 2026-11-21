{ DIALECT: vintage extended }
{ NEW-24r: shadowing a CONST capacity name in an inner scope with a
  smaller CONST or a variable must not let UPPER/LOWER of an outer wide
  string narrow silently into an INTEGER. }
PROGRAM StringBoundShadowedConstNarrowing(OUTPUT);
CONST
  BIG = 40000;
TYPE
  BigAlias = LSTRING(BIG);
  Rec = RECORD
    f: STRING(BIG)
  END;
VAR
  s: STRING(BIG);
  a: BigAlias;
  r: Rec;

PROCEDURE ShadowWithSmall;
CONST
  BIG = 10;
VAR
  i: INTEGER;
BEGIN
  i := UPPER(s);
  i := LOWER(a);
  i := UPPER(r.f)
END;

PROCEDURE ShadowWithVar;
VAR
  BIG: INTEGER;
  i: INTEGER;
BEGIN
  BIG := 10;
  i := UPPER(s)
END;

BEGIN
  ShadowWithSmall;
  ShadowWithVar
END.
