PROGRAM forward_pointer_types(OUTPUT);
{ A pointer type may name a type declared later in the same TYPE section:
  a linked list, mutually recursive records, a record pointing at itself
  (also through a variant record), a pointer to a later ARRAY, and a
  pointer to a pointer. In a routine's TYPE section the later local
  declaration wins over an outer type of the same name. Regression guard:
  both the typechecker and codegen resolved a pointer's base eagerly, so
  every forward reference was an unknown type. }
TYPE
  Node = RECORD v: INTEGER END;
  PList = ^Cell;
  Cell = RECORD val: INTEGER; next: PList END;
  PA = ^RA;
  PB = ^RB;
  RA = RECORD n: INTEGER; b: PB END;
  RB = RECORD m: INTEGER; a: PA END;
  PArr = ^Arr;
  Arr = ARRAY [1..3] OF INTEGER;
  PPC = ^PC;
  PC = ^Cell;
  Self = RECORD k: INTEGER; me: ^Self END;
  Tagged = RECORD
    nx: ^Tagged;
    CASE t: INTEGER OF
      0: (i: INTEGER);
      1: (c: CHAR)
  END;
VAR
  head, p: PList;
  i, sum: INTEGER;
  a: PA;
  b: PB;
  pa: PArr;
  x: Arr;
  pc: PC;
  ppc: PPC;
  s: Self;
  tg: Tagged;

PROCEDURE Push(VAR h: PList; v: INTEGER);
VAR c: PList;
BEGIN
  NEW(c);
  c^.val := v;
  c^.next := h;
  h := c
END;

PROCEDURE Local;
TYPE
  PNode = ^Node;
  Node = RECORD v, w: INTEGER; next: PNode END;
VAR q, r0: PNode;
  PROCEDURE Inner;
  VAR r: PNode;
  BEGIN
    NEW(r);
    r^.w := 11;
    WRITELN(r^.w)
  END;
BEGIN
  NEW(q);
  NEW(r0);
  q^.next := r0;
  q^.next^.w := 9;
  WRITELN(q^.next^.w, ' ', SIZEOF(Node));
  Inner
END;

BEGIN
  head := NIL;
  FOR i := 1 TO 4 DO Push(head, i);
  sum := 0;
  p := head;
  WHILE p <> NIL DO
  BEGIN
    sum := sum + p^.val;
    p := p^.next
  END;
  WRITELN(sum, ' ', head^.val);
  WITH head^ DO WRITELN(next^.val);
  NEW(a);
  NEW(b);
  a^.b := b;
  b^.a := a;
  b^.m := 5;
  a^.n := 6;
  WRITELN(a^.b^.m, ' ', b^.a^.n, ' ', a^.b^.a^.b^.m);
  x[2] := 7;
  NEW(pa);
  pa^ := x;
  WRITELN(pa^[2]);
  pc := head;
  ppc := ADR pc;
  WRITELN(ppc^^.val);
  s.k := 3;
  s.me := ADR s;
  WRITELN(s.me^.me^.k);
  tg.t := 0;
  tg.i := 12;
  tg.nx := ADR tg;
  WRITELN(tg.nx^.i);
  Local;
  WRITELN(SIZEOF(Node))
END.
