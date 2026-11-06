{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM encode_builtins;
{ ENCODE(D, X:M:N) formats X exactly as WRITE(X:M:N) into the LSTRING D and
  returns FALSE, leaving D unchanged, when the text does not fit. }
TYPE str10 = LSTRING(10);
     small = 1..9;
     rec = RECORD n: INTEGER END;
VAR s: str10; t: LSTRING(3); u: LSTRING(255);
    i: INTEGER; w: WORD; r: REAL; b: BOOLEAN; c: CHAR; n: small; k: INTEGER;
    rc: rec; p: ^INTEGER;
PROCEDURE show(ok: BOOLEAN);
BEGIN
  IF ok THEN WRITELN('[', s, ']') ELSE WRITELN('no [', s, ']')
END;
PROCEDURE showt(ok: BOOLEAN);
BEGIN
  IF ok THEN WRITELN('[', t, ']') ELSE WRITELN('no [', t, ']')
END;
PROCEDURE showu(ok: BOOLEAN);
BEGIN
  IF ok THEN WRITELN('[', u, ']') ELSE WRITELN('no [', u, ']')
END;
FUNCTION bump: INTEGER;
BEGIN k := k + 1; bump := k END;
PROCEDURE viaformal(VAR d: str10; x: INTEGER);
BEGIN IF ENCODE(d, x:4) THEN WRITELN('<', d, '>') END;
BEGIN
  k := 0;
  { INTEGER: width pads on the left and never truncates }
  i := -123;
  show(ENCODE(s, i));
  show(ENCODE(s, i:6));
  show(ENCODE(s, i:2));
  show(ENCODE(s, 0));
  show(ENCODE(s, MAXINT));
  show(ENCODE(s, -MAXINT - 1));
  show(ENCODE(s, i * 2 + 1));
  { WORD }
  w := 65535;
  show(ENCODE(s, w));
  show(ENCODE(s, w:7));
  { REAL: WRITE's fixed and exponent forms }
  r := 3.25;
  show(ENCODE(s, r:8:2));
  show(ENCODE(s, r:0:1));
  showu(ENCODE(u, r));
  showu(ENCODE(u, r:10));
  showu(ENCODE(u, r::3));
  show(ENCODE(s, r));
  { BOOLEAN }
  b := FALSE;
  show(ENCODE(s, b));
  show(ENCODE(s, NOT b:7));
  t := 'ab';
  showt(ENCODE(t, b));
  { CHAR }
  c := 'x';
  show(ENCODE(s, c));
  show(ENCODE(s, c:3));
  { subrange, selected and dereferenced values }
  n := 7;
  show(ENCODE(s, n:bump));
  WRITELN(k);
  rc.n := 42;
  show(ENCODE(s, rc.n:5));
  NEW(p);
  p^ := 9;
  show(ENCODE(s, p^));
  DISPOSE(p);
  { X and M evaluate once each }
  show(ENCODE(s, bump));
  WRITELN(k);
  show(ENCODE(s, i:k + 4));
  { too long: FALSE and the destination keeps its old value }
  showt(ENCODE(t, 1234));
  showt(ENCODE(t, 123));
  showt(ENCODE(t, -12));
  { a VAR LSTRING formal is a bare destination }
  viaformal(s, 77);
  WRITELN(ENCODE(s, i + 1), ' ', s);
END.
