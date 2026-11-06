{ DIALECT: vintage extended }
{ CMP-24: a field or index selector on a parameterless function name
  outside its own body calls the function once per occurrence and selects
  from the result, including nested, string and pointer selectors.
  Inside an aggregate function's own body the selected name is the
  result variable, so selected stores and reads stay on it. }
PROGRAM NiladicResultSelect(OUTPUT);
TYPE
  inner = RECORD g: INTEGER END;
  rec = RECORD f: INTEGER; inn: inner END;
  arr = ARRAY [1..3] OF INTEGER;
  holder = RECORD a: arr END;
  name5 = STRING(5);
  named = RECORD n: name5; k: INTEGER END;
  pnamed = ^named;
VAR
  calls: INTEGER;
  gp: pnamed;
FUNCTION mk: rec;
VAR t: rec;
BEGIN
  t.f := 7;
  mk := t
END;
FUNCTION built: rec;
BEGIN
  calls := calls + 1;
  built.f := 1;
  built.inn.g := 42;
  built.f := built.f + 6
END;
FUNCTION g: arr;
BEGIN
  g[1] := 10;
  g[2] := 20;
  g[3] := g[1] + g[2]
END;
FUNCTION h: holder;
BEGIN
  h.a[1] := 1;
  h.a[2] := 5;
  h.a[3] := 9
END;
FUNCTION nm: named;
BEGIN
  nm.n := 'hello';
  nm.k := 2
END;
FUNCTION word: name5;
BEGIN
  word := 'abcde';
  word[2] := 'X'
END;
FUNCTION gptr: pnamed;
BEGIN
  gptr := gp
END;
BEGIN
  calls := 0;
  NEW(gp);
  gp^.k := 99;
  WRITELN(mk.f);
  WRITELN(built.f, ' ', built.inn.g);
  WRITELN(g[2], ' ', g[3]);
  WRITELN(h.a[2]);
  WRITELN(built.f + built.inn.g);
  IF mk.f = 7 THEN WRITELN('compare ok');
  WRITELN(nm.n, ' ', nm.n[nm.k]);
  WRITELN(word[2], word[3]);
  WRITELN(gptr^.k);
  WRITELN(calls)
END.
