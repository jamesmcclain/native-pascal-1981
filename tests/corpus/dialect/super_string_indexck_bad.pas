{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-29: $INDEXCK guards a conformant STRING/LSTRING formal's subscript
  like a SUPER ARRAY's, against its declared lower (1 or 0) and the UPPER
  its caller passed, since its storage is only the actual's. Index 4 of a
  STRING(3) passed whole fails before any store. }
PROGRAM SuperStringIndexckBad(OUTPUT);
VAR
  a: STRING(3);
  l: LSTRING(4);

PROCEDURE Poke(VAR s: STRING; k: INTEGER);
BEGIN
  s[k] := 'z';
  WRITELN('stored at ', k, ' of ', UPPER(s));
END;

PROCEDURE PeekL(CONST s: LSTRING; k: INTEGER);
BEGIN
  WRITELN('read index ', k, ' of ', UPPER(s), ': ', ORD(s[k]) >= 0);
END;

BEGIN
  a := 'abc';
  l := 'ab';
  Poke(a, 3);
  Poke(l, 2);
  PeekL(l, 0);
  PeekL(l, 4);
  WRITELN(a, ' ', l);
  Poke(a, 4);
  WRITELN('not reached');
END.
