{ DIALECT: vintage extended }
{ NEW-24: the typechecker types LOWER and UPPER of a string with a
  capacity above 32767 as WORD wherever the string is reached, so they do
  not narrow into an INTEGER without RETYPE. }
PROGRAM StringBoundNarrowing(OUTPUT);
TYPE
  Big = LSTRING(40000);
  Rec = RECORD
    f: Big
  END;
VAR
  l: Big;
  s: STRING(32768);
  r: Rec;
  a: ARRAY [1..2] OF Big;
  i: INTEGER;

FUNCTION F: Big;
BEGIN
  F := 'xy'
END;

BEGIN
  i := UPPER(l);
  i := LOWER(s);
  i := UPPER(r.f);
  i := UPPER(a[2]);
  i := UPPER(F)
END.
