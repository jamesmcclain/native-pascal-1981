{ DIALECT: extended }
PROGRAM nestok;
TYPE Tree = ^Node;
     Node = RECORD key: INTEGER; left, right: Tree END;
     PT = ^Tree;
     Cells = SUPER ARRAY [1..*] OF CHAR;
     PC = ^Cells;
     Holder = RECORD n: INTEGER; cells: PC; kids: ARRAY [1..2] OF Tree END;
     PH = ^Holder;
     Pair = RECORD a, b: INTEGER END;
     PP = ^Pair;
     V = RECORD CASE k: BOOLEAN OF TRUE: (i: INTEGER); FALSE: (c: CHAR) END;
     PV = ^V;
FUNCTION insert(t: Tree; k: INTEGER): Tree;
BEGIN
  IF t = NIL THEN BEGIN NEW(t); t^.key := k; t^.left := NIL; t^.right := NIL END
  ELSE IF k < t^.key THEN t^.left := insert(t^.left, k)
  ELSE t^.right := insert(t^.right, k);
  insert := t
END;
FUNCTION sum(t: Tree): INTEGER;
BEGIN IF t = NIL THEN sum := 0 ELSE sum := t^.key + sum(t^.left) + sum(t^.right) END;
PROCEDURE clear(VAR p: Pair);
BEGIN p.a := 0; p.b := -32768 END;
FUNCTION total(CONST p: Pair): INTEGER;
BEGIN total := p.a + p.b END;
FUNCTION copied(p: Pair): INTEGER;
BEGIN copied := p.b END;
PROCEDURE probe;
VAR t: Tree; pt: PT; h: PH; p: PP; v: PV; i: INTEGER;
BEGIN
  {$INITCK+}
  t := NIL;
  FOR i := 1 TO 5 DO t := insert(t, (i * 3) MOD 7);
  WRITELN(sum(t));
  NEW(pt); pt^ := t; NEW(pt^^.left^.left); pt^^.left^.left^.key := 9;
  WRITELN(pt^^.key, ' ', pt^^.left^.left^.key);
  NEW(h); h^.n := 2; NEW(h^.cells, 2); h^.cells^[1] := 'o'; h^.cells^[2] := 'k';
  h^.kids[1] := t; h^.kids[2] := NIL;
  WRITELN(h^.cells^[1], h^.cells^[2], ' ', UPPER(h^.cells^), ' ', h^.kids[1]^.key);
  NEW(p); clear(p^); WRITELN(total(p^), ' ', copied(p^));
  NEW(v); v^.k := FALSE; v^.c := 'z'; WRITELN(v^.c);
  v^.i := 5; WRITELN(v^.i);
  { A nested WITH cannot tell which target binds a name: its outer heap
    target is released (an enabled read inside is a boundary), and later
    checked reads of the referent never fail. }
  {$INITCK-} WITH h^ DO WITH kids[1]^ DO key := n; {$INITCK+}
  WRITELN(h^.kids[1]^.key)
  {$INITCK-}
END;
BEGIN probe END.
