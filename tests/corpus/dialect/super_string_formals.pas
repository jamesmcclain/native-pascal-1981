{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-29: VAR and CONST formals of the super-array types STRING and
  LSTRING themselves are conformant (IBM manual 6-13..6-19, 6-38, 10-9).
  A STRING formal takes a STRING(n) of any n, an LSTRING(n) (its current
  length is the formal's UPPER), a CHAR, and as CONST also a literal, a
  string or CHAR CONST name and a function result; an LSTRING formal
  takes an LSTRING(n) of any n, and as CONST also a constant, which
  converts to LSTRING. UPPER inside the routine is the actual's; writes
  go back through VAR; the string procedures, WRITE, READ, comparisons of
  an LSTRING formal, FORWARD headings and passing a formal on all work.
  Both formals used to be capacity 256: a literal stopped codegen with
  "string literal length does not match STRING capacity" and any other
  capacity with "VAR argument type mismatch". }
PROGRAM SuperStringFormals(INPUT, OUTPUT);
CONST
  GREETING = 'hello';
  BANG = '!';
VAR
  a: STRING(5);
  b: STRING(12);
  l: LSTRING(100);
  m: LSTRING(3);
  c: CHAR;
  n: INTEGER;
  ok: BOOLEAN;

PROCEDURE Show(CONST s: STRING);
VAR k: INTEGER;
BEGIN
  WRITE('[', s, '] upper ', UPPER(s), ' lower ', LOWER(s), ' chars:');
  FOR k := 1 TO UPPER(s) DO WRITE(' ', s[k]);
  WRITELN;
END;

PROCEDURE ShowL(CONST s: LSTRING);
BEGIN
  WRITELN('<', s, '> upper ', UPPER(s), ' lower ', LOWER(s), ' len ',
    ORD(s[0]), ' ', ORD(s.LEN));
END;

PROCEDURE Upcase(VAR s: STRING);
VAR k: INTEGER;
BEGIN
  FOR k := 1 TO UPPER(s) DO
    IF (s[k] >= 'a') AND (s[k] <= 'z') THEN
      s[k] := CHR(ORD(s[k]) - 32);
  Show(s);
END;

PROCEDURE Append(VAR d: LSTRING; CONST s: STRING);
BEGIN
  CONCAT(d, s);
  ShowL(d);
END;

PROCEDURE Truncate(VAR d: LSTRING; k: INTEGER);
BEGIN
  d[0] := CHR(k);
END;

PROCEDURE Fill(VAR d: LSTRING);
BEGIN
  COPYLST('copied', d);
  INSERT('<', d, 1);
  DELETE(d, 2, 1);
  IF d = '<opied' THEN WRITELN('lstring formal compares equal');
  IF d < 'zzz' THEN WRITELN('lstring formal compares less');
END;

PROCEDURE Pad(VAR s: STRING);
BEGIN
  COPYSTR('ab', s);
  Show(s);
END;

FUNCTION Count(CONST s: STRING; ch: CHAR): INTEGER;
VAR k, total: INTEGER;
BEGIN
  total := 0;
  FOR k := 1 TO UPPER(s) DO
    IF s[k] = ch THEN total := total + 1;
  Count := total;
END;

FUNCTION Five: STRING(5);
BEGIN
  Five := 'fives';
END;

PROCEDURE Inner(CONST s: STRING); FORWARD;

PROCEDURE ViaL(VAR d: LSTRING);
BEGIN
  Inner(d);
END;

PROCEDURE Middle(VAR s: STRING);
BEGIN
  Inner(s);
  s[UPPER(s)] := '*';
END;

PROCEDURE Inner(CONST s: STRING);
BEGIN
  WRITELN('inner [', s:8, '] ', UPPER(s), ' pos ', POSITN('b', s, 1));
END;

PROCEDURE Enc(VAR d: LSTRING);
BEGIN
  ok := ENCODE(d, 12345:7);
  WRITELN('encode ', ok, ' [', d, '] ', ORD(d.LEN));
END;

PROCEDURE Dec(CONST s: STRING);
BEGIN
  ok := DECODE(s, n);
  WRITELN('decode ', ok, ' ', n);
END;

PROCEDURE Rd(VAR d: LSTRING; VAR s: STRING);
BEGIN
  READLN(d);
  READLN(s);
END;

PROCEDURE SetFirst(VAR s: STRING);
BEGIN
  s[1] := 'k';
END;

BEGIN
  a := 'abcde';
  b := 'twelve chars';
  Show(a);
  Show(b);
  Show('lit');
  Show(GREETING);
  Show('x');
  Show(BANG);
  Show('');
  Show(Five);
  c := 'q';
  Show(c);
  SetFirst(c);
  WRITELN('char written through VAR: ', c);
  l := 'an lstring';
  Show(l);
  ShowL(l);
  ShowL('literal');
  ShowL(GREETING);
  ShowL('z');
  ShowL('');
  Upcase(a);
  WRITELN('after upcase: ', a);
  Upcase(l);
  WRITELN('after upcase: ', l);
  Append(l, ' more');
  Append(l, a);
  Truncate(l, 2);
  WRITELN('truncated: ', l);
  Fill(l);
  WRITELN('filled: ', l);
  Pad(a);
  WRITELN('padded: [', a, ']');
  m := 'ab';
  Append(m, 'c');
  WRITELN('count: ', Count('banana', 'a'), ' ', Count(b, 'e'), ' ', Count(l, 'o'));
  a := 'abcde';
  Middle(a);
  WRITELN('middle: ', a);
  l := 'xbcz';
  ViaL(l);
  Enc(l);
  Dec('  42');
  Dec(l);
  Rd(l, a);
  WRITELN('read [', l, '] [', a, ']');
END.
