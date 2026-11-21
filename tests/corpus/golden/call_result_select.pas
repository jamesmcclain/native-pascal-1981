{ DIALECT: vintage extended }
{ CMP-24r: postfix selectors (.field, [i], ^) on a function call with
  arguments work in general expressions, calling the function once per
  occurrence and selecting from the result, including nested records,
  arrays, strings, pointers, CONST string formals and SUCC/PRED subrange
  domains. }
PROGRAM CallResultSelect(OUTPUT);
TYPE
  inner = RECORD g: INTEGER END;
  rec = RECORD f: INTEGER; inn: inner END;
  arr = ARRAY [1..3] OF INTEGER;
  holder = RECORD a: arr END;
  name5 = STRING(5);
  named = RECORD n: name5; k: INTEGER END;
  pnamed = ^named;
  small = 1..5;
  subrec = RECORD s: small END;
VAR
  calls: INTEGER;
  gp: pnamed;
FUNCTION mk(v: INTEGER): rec;
VAR t: rec;
BEGIN
  t.f := v;
  t.inn.g := v * 6;
  mk := t
END;
FUNCTION built(base: INTEGER): rec;
BEGIN
  calls := calls + 1;
  built.f := base;
  built.inn.g := base * 21;
  built.f := built.f + 6
END;
FUNCTION g(step: INTEGER): arr;
BEGIN
  g[1] := step;
  g[2] := step * 2;
  g[3] := g[1] + g[2]
END;
FUNCTION h(mid: INTEGER): holder;
BEGIN
  h.a[1] := 1;
  h.a[2] := mid;
  h.a[3] := 9
END;
FUNCTION nm(s: name5; idx: INTEGER): named;
BEGIN
  nm.n := s;
  nm.k := idx
END;
FUNCTION word(s: name5): name5;
BEGIN
  word := s;
  word[2] := 'X'
END;
FUNCTION gptr(p: pnamed): pnamed;
BEGIN
  gptr := p
END;
FUNCTION mksub(v: small): subrec;
BEGIN
  mksub.s := v
END;
PROCEDURE echo_str(CONST s: STRING);
BEGIN
  WRITELN(s, ' ', UPPER(s))
END;
BEGIN
  calls := 0;
  NEW(gp);
  gp^.k := 99;
  WRITELN(mk(7).f);
  WRITELN(built(1).f, ' ', built(2).inn.g);
  WRITELN(g(10)[2], ' ', g(10)[3]);
  WRITELN(h(5).a[2]);
  WRITELN(built(1).f + built(2).inn.g);
  IF mk(7).f = 7 THEN WRITELN('compare ok');
  WRITELN(nm('hello', 2).n, ' ', nm('hello', 2).n[nm('hello', 2).k]);
  IF nm('hello', 2).n = 'hello' THEN WRITELN('str compare ok');
  echo_str(nm('hello', 2).n);
  WRITELN(word('abcde')[2], word('abcde')[3]);
  WRITELN(gptr(gp)^.k);
  WRITELN(SUCC(mksub(2).s));
  WRITELN(calls)
END.
