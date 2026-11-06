{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-29: a length byte stored through a conformant LSTRING formal is
  checked against the actual's capacity (here 3), even through index
  zero; the bound is not the formal type's placeholder capacity. }
PROGRAM SuperStringLengthRangeckBad(OUTPUT);
VAR
  l: LSTRING(3);

PROCEDURE SetLen(VAR s: LSTRING; k: INTEGER);
BEGIN
  s[0] := CHR(k);
  WRITELN('length ', ORD(s.LEN), ' of ', UPPER(s));
END;

BEGIN
  l := 'abc';
  SetLen(l, 3);
  SetLen(l, 4);
  WRITELN('not reached');
END.
