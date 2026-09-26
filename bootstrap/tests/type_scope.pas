{ A routine-local TYPE is scoped: it hides an outer TYPE inside its routine
  only, siblings may reuse a name, and an alias is a second name for its
  target. The native compiler's tests/golden/type_scope_shadowing.pas checks
  the same rules. }
(*$INCLUDE:'testio.inc'*)
PROGRAM type_scope(input, output);
USES testio;

TYPE
  Buf = ARRAY [1..2] OF INTEGER;
  A = RECORD x: INTEGER END;
  B = A;

VAR
  g: Buf;
  p: A;
  q: B;

PROCEDURE Outer;
TYPE
  Buf = ARRAY [1..5] OF INTEGER;
VAR
  t: Buf;
BEGIN
  t[5] := 3;
  WriteInt(t[5]); WriteInt(SIZEOF(t)); WRITELN;
END;

PROCEDURE SiblingA;
TYPE
  Loc = ARRAY [1..3] OF INTEGER;
VAR
  c: Loc;
BEGIN
  c[3] := 2;
  WriteInt(c[3]); WriteInt(SIZEOF(c)); WRITELN;
END;

PROCEDURE SiblingB;
TYPE
  Loc = RECORD a, b: INTEGER END;
VAR
  d: Loc;
BEGIN
  d.b := 5;
  WriteInt(d.b); WriteInt(SIZEOF(d)); WRITELN;
END;

BEGIN
  Outer;
  SiblingA;
  SiblingB;
  g[2] := 8;
  p.x := 9;
  q := p;
  WriteInt(g[2]); WriteInt(SIZEOF(g)); WriteInt(q.x); WriteInt(p.x); WRITELN;
END.
