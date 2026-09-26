PROGRAM type_scope_shadowing(OUTPUT);
{ A routine-local TYPE is scoped like any other declaration: it hides an
  outer TYPE of the same name inside its routine (and the routines nested
  in it) only, and sibling routines may each declare their own. An alias
  is a second name for its target, not a rename of it. Regression guard:
  codegen kept a type's one name on its table entry, never scoped it, so a
  reused name was rejected as a duplicate, and `TYPE B = A' renamed A so a
  later use of A was undeclared. }
TYPE
  Node = RECORD v: INTEGER END;
  Buf = ARRAY [1..2] OF INTEGER;
  A = RECORD x: INTEGER END;
  B = A;
VAR
  n: Node;
  g: Buf;
  p: A;
  q: B;

PROCEDURE Outer;
TYPE
  Node = RECORD v, w: INTEGER END;
  PNode = ^Node;
  Buf = ARRAY [1..5] OF INTEGER;
VAR
  pn: PNode;
  PROCEDURE Inner;
  VAR t: Buf;
  BEGIN
    t[5] := 3;
    WRITELN(t[5], ' ', UPPER(t), ' ', SIZEOF(Buf))
  END;
BEGIN
  NEW(pn);
  pn^.w := 6;
  WRITELN(pn^.w, ' ', SIZEOF(Node));
  Inner
END;

PROCEDURE SiblingA;
TYPE Loc = ARRAY [1..3] OF INTEGER;
VAR c: Loc;
BEGIN
  c[3] := 2;
  WRITELN(c[3], ' ', UPPER(c))
END;

PROCEDURE SiblingB;
TYPE Loc = RECORD a, b: INTEGER END;
VAR d: Loc;
BEGIN
  d.b := 5;
  WRITELN(d.b, ' ', SIZEOF(Loc))
END;

PROCEDURE LocalEnums;
TYPE Color = (Red, Green);
BEGIN
  WRITELN(ORD(Green))
END;

PROCEDURE OtherEnums;
TYPE Color = (Blue, Cyan, Green);
BEGIN
  WRITELN(ORD(Green))
END;

BEGIN
  Outer;
  SiblingA;
  SiblingB;
  LocalEnums;
  OtherEnums;
  n.v := 1;
  g[2] := 8;
  p.x := 9;
  q := p;
  WRITELN(n.v, ' ', SIZEOF(Node), ' ', g[2], ' ', UPPER(g), ' ', q.x)
END.
