{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM decode_builtins;
{ DECODE(S, X:M:N) converts the text of S to X as READ would and returns
  FALSE, leaving X unchanged, for a malformed or out-of-range text. The
  subrange rejections below hold with RANGECK off: they are results, not
  traps. }
{$RANGECK-}
TYPE small = 1..9;
     capital = 'A'..'Z';
     rec = RECORD n: INTEGER END;
VAR s: LSTRING(20); f: STRING(5);
    i: INTEGER; w: WORD; r: REAL; b: BOOLEAN; c: CHAR; u: capital; n: small;
    k: INTEGER; a: ARRAY [1..2] OF INTEGER; rc: rec; p: ^INTEGER;
FUNCTION bump: INTEGER;
BEGIN k := k + 1; bump := k END;
FUNCTION text: LSTRING(4);
BEGIN text := ' 21 ' END;
PROCEDURE viaformal(VAR x: INTEGER);
BEGIN IF DECODE(' 77 ', x) THEN WRITELN('<', x, '>') END;
BEGIN
  k := 0;
  { INTEGER: sign, blanks and tabs at either end, leading zeros, limits }
  i := 999;
  s := ' -123 ';
  WRITELN(DECODE(s, i), ' ', i);
  WRITELN(DECODE('+45', i), ' ', i);
  WRITELN(DECODE('0042', i), ' ', i);
  WRITELN(DECODE('32767', i), ' ', i);
  WRITELN(DECODE('32768', i), ' ', i);
  WRITELN(DECODE('-32768', i), ' ', i);
  WRITELN(DECODE('-32769', i), ' ', i);
  WRITELN(DECODE('12x', i), ' ', i);
  WRITELN(DECODE('', i), ' ', i);
  WRITELN(DECODE('   ', i), ' ', i);
  WRITELN(DECODE('1 2', i), ' ', i);
  WRITELN(DECODE('-', i), ' ', i);
  WRITELN(DECODE('99999999999999999999999', i), ' ', i);
  { fixed STRING, function result and single-character sources }
  f := ' 6   ';
  WRITELN(DECODE(f, i), ' ', i);
  WRITELN(DECODE(text, i), ' ', i);
  WRITELN(DECODE('7', i), ' ', i);
  { WORD }
  w := 1;
  WRITELN(DECODE('65535', w), ' ', w);
  WRITELN(DECODE('65536', w), ' ', w);
  WRITELN(DECODE('-1', w), ' ', w);
  WRITELN(DECODE('-0', w), ' ', w);
  { a subrange rejects out-of-range values whatever RANGECK says }
  n := 5;
  WRITELN(DECODE('9', n), ' ', n);
  WRITELN(DECODE('10', n), ' ', n);
  WRITELN(DECODE('0', n), ' ', n);
  { CHAR: exactly one character once the blanks are dropped }
  c := '?';
  WRITELN(DECODE(' x ', c), ' ', c);
  WRITELN(DECODE('xy', c), ' ', c);
  WRITELN(DECODE(' ', c), ' ', c);
  u := 'A';
  WRITELN(DECODE('Q', u), ' ', u);
  WRITELN(DECODE('q', u), ' ', u);
  { BOOLEAN: the names without regard to case, or 0 and 1 }
  b := FALSE;
  WRITELN(DECODE('TRUE', b), ' ', b);
  WRITELN(DECODE('false', b), ' ', b);
  WRITELN(DECODE('1', b), ' ', b);
  WRITELN(DECODE('2', b), ' ', b);
  WRITELN(DECODE('yes', b), ' ', b);
  { REAL }
  r := 0.0;
  WRITELN(DECODE('3.25', r), ' ', r:6:2);
  WRITELN(DECODE(' 1e3 ', r), ' ', r:8:1);
  WRITELN(DECODE('.5', r), ' ', r:6:2);
  WRITELN(DECODE('5.', r), ' ', r:6:2);
  WRITELN(DECODE('-7', r), ' ', r:6:2);
  WRITELN(DECODE('1.2.3', r), ' ', r:6:2);
  WRITELN(DECODE('', r), ' ', r:6:2);
  { selected and dereferenced destinations, a VAR formal }
  a[2] := 0;
  rc.n := 0;
  NEW(p);
  p^ := 0;
  WRITELN(DECODE('11', a[2]), ' ', a[2]);
  WRITELN(DECODE('12', rc.n), ' ', rc.n);
  WRITELN(DECODE('13', p^), ' ', p^);
  DISPOSE(p);
  viaformal(i);
  { M and N are accepted, evaluated once and ignored }
  WRITELN(DECODE('8', i:bump:bump), ' ', i, ' ', k);
  IF DECODE('5', i) THEN WRITELN('five ', i);
END.
