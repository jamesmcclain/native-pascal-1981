{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-47: ^STRING and ^LSTRING pointer referents are super-array pointers
  allocated with NEW(p, n), carrying a host descriptor (IBM manual
  6-14..6-19). LOWER(p^) is 1/0, UPPER(p^) is the allocated capacity,
  indexing and .LEN work with dynamic bounds, WRITE/READ and string
  builtins accept p^, and p^ can be passed to conformant STRING/LSTRING
  formals. Named aliases and inline ^STRING/^LSTRING share one type. }
PROGRAM SuperStringPointers(INPUT, OUTPUT);
TYPE
  PLStr = ^LSTRING;
  PStr = ^STRING;
  Holder = RECORD
    lp: PLStr;
    sp: ^STRING
  END;
VAR
  p, q: PLStr;
  inline_l: ^LSTRING;
  p0: ^LSTRING;
  s: PStr;
  inline_s: ^STRING;
  h: Holder;
  fixed_l: LSTRING(20);
  fixed_s: STRING(5);
  n: INTEGER;
  ok: BOOLEAN;

PROCEDURE ShowS(CONST x: STRING);
BEGIN
  WRITELN('S[', x, '] ', LOWER(x), '..', UPPER(x));
END;

PROCEDURE ShowL(CONST x: LSTRING);
BEGIN
  WRITELN('L<', x, '> ', LOWER(x), '..', UPPER(x), ' len ', ORD(x.LEN));
END;

PROCEDURE FillL(VAR d: LSTRING; CONST src: STRING);
BEGIN
  COPYLST(src, d);
  CONCAT(d, '!');
END;

PROCEDURE FillS(VAR d: STRING; CONST src: STRING);
BEGIN
  COPYSTR(src, d);
END;

FUNCTION EchoL(x: PLStr): ^LSTRING;
BEGIN
  EchoL := x;
END;

BEGIN
  NEW(p, 10);
  NEW(s, 5);
  NEW(p0, 0);
  WRITELN('bounds ', LOWER(p^), '..', UPPER(p^), ' ',
          LOWER(s^), '..', UPPER(s^), ' ', LOWER(p0^), '..', UPPER(p0^));

  p^.LEN := CHR(4);
  p^[1] := 'a'; p^[2] := 'b'; p^[3] := 'c'; p^[4] := 'd';
  WRITELN('lstr [', p^, '] len ', ORD(p^.LEN), ' ', ORD(p^[0]));

  s^[1] := 'h'; s^[2] := 'e'; s^[3] := 'l'; s^[4] := 'l'; s^[5] := 'o';
  WRITELN('str [', s^, ']');

  inline_l := p;
  inline_s := s;
  q := EchoL(inline_l);
  WRITELN('eq ', q = p, ' upper ', UPPER(EchoL(p)^));

  h.lp := p;
  h.sp := s;
  WRITELN('holder ', UPPER(h.lp^), ' ', UPPER(h.sp^));

  ShowL(p^);
  ShowS(p^);
  ShowS(s^);

  FillL(p^, 'hi');
  ShowL(p^);
  WRITELN('cmp ', p^ = 'hi!', ' ', p^ < 'hz', ' ', p^ = q^);

  FillS(s^, 'xy');
  ShowS(s^);

  COPYLST(p^, fixed_l);
  COPYSTR(s^, fixed_s);
  WRITELN('copied [', fixed_l, '] [', fixed_s, ']');
  WRITELN('positn ', POSITN('i', p^, 1), ' ', POSITN('y', s^, 1));

  READLN(p^);
  READLN(s^);
  WRITELN('read [', p^, '] len ', ORD(p^.LEN), ' [', s^, ']');
  ok := DECODE(p^, n);
  WRITELN('decode ', ok, ' ', n);

  p0^.LEN := CHR(0);
  WRITELN('empty [', p0^, ']');

  DISPOSE(p0);
  DISPOSE(s);
  DISPOSE(p);
END.
