{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-29: $RANGECK checks a length stored into a conformant LSTRING
  formal (.LEN or index zero, and CONCAT, COPYLST, INSERT and ENCODE) against
  its actual's capacity, not the placeholder capacity of the formal's
  type. A length within LSTRING(4) passes; CONCAT to length 5 fails before
  any byte is written. }
PROGRAM SuperStringRangeckBad(OUTPUT);
VAR
  l: LSTRING(4);

PROCEDURE SetLen(VAR s: LSTRING; k: INTEGER);
BEGIN
  s.LEN := CHR(k);
  WRITELN('length ', ORD(s[0]), ' of ', UPPER(s));
END;

PROCEDURE Cat(VAR s: LSTRING; CONST t: STRING);
BEGIN
  CONCAT(s, t);
  WRITELN('concat [', s, ']');
END;

BEGIN
  l := 'ab';
  SetLen(l, 4);
  SetLen(l, 1);
  Cat(l, 'xyz');
  Cat(l, 'q');
  WRITELN('not reached');
END.
