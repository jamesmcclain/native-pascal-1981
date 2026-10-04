PROGRAM heapok;
TYPE PR = ^R;
     Pair = RECORD a, b: INTEGER END;
     R = RECORD v, w: INTEGER; c: CHAR; ok: BOOLEAN; next: PR;
                inner: Pair; row: ARRAY [1..3] OF CHAR END;
     PI = ^INTEGER;
     PA = ^ARRAY [1..4] OF INTEGER;
PROCEDURE setv(VAR x: INTEGER; n: INTEGER);
BEGIN x := n END;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; y := t END;
FUNCTION total(p: Pair): INTEGER;
BEGIN total := p.a + p.b END;
PROCEDURE probe(k: INTEGER);
VAR p, q, head: PR; ip: PI; ap: PA; i, sum: INTEGER; r: Pair;
BEGIN
  {$INITCK+}
  NEW(p); p^.v := 0; p^.next := NIL; p^.c := 'h'; p^.ok := FALSE;
  ip := NIL; NEW(ip); ip^ := -32768;
  NEW(ap); FOR i := 1 TO 4 DO ap^[i] := i * k;
  WRITELN(p^.v, ' ', ip^, ' ', ap^[k + 1], ' ', p^.c, ORD(p^.ok), ' ', p^.next = NIL);
  { A linked list built and walked with every read checked. }
  head := NIL;
  FOR i := 1 TO 3 DO BEGIN NEW(q); q^.v := i; q^.next := head; head := q END;
  sum := 0; q := head;
  WHILE q <> NIL DO BEGIN sum := sum + q^.v; q := q^.next END;
  WRITELN('sum ', sum);
  { Another pointer to the same referent shares its state. }
  q := p; q^.w := 7; WRITELN(p^.w);
  { Producers: WITH-bound fields, VAR bindings, nested components. }
  WITH p^ DO BEGIN inner.a := v + 1; row[2] := c END;
  setv(p^.inner.b, 5); swap(p^.inner.a, p^.inner.b);
  WRITELN(p^.inner.a, ' ', p^.inner.b, ' ', p^.row[2]);
  { Whole copies and value actuals of fully written heap aggregates. }
  r := p^.inner; NEW(q); q^.inner := r; q^.inner := p^.inner;
  WRITELN(total(q^.inner), ' ', total(p^.inner));
  DISPOSE(p); DISPOSE(ip); DISPOSE(ap)
  {$INITCK-}
END;
BEGIN probe(1); probe(3) END.
