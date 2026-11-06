{ DIALECT: vintage }
{ OPT: 0 2 }
PROGRAM LargeAggregateResultsVintage(output);
{ NEW-35 in the vintage dialect: an LSTRING(65535) function result (65,536
  bytes, the most a vintage type can hold) assigned, nested, written and
  compared, at O0 and O2. clang crashed at O0 on its whole-value copy. }
TYPE
  Big = LSTRING(65535);
VAR
  s, t: Big;

FUNCTION MakeBig(c: CHAR): Big;
BEGIN
  MakeBig := 'vintage';
  MakeBig[1] := c;
END;

FUNCTION Nested(c: CHAR): Big;
BEGIN
  Nested := MakeBig(c);
END;

BEGIN
  s := MakeBig('V');
  t := Nested('W');
  WRITELN(s, ' ', t);
  WRITELN(Nested('X'));
  IF Nested('V') = s THEN WRITELN('equal') ELSE WRITELN('differ');
END.
