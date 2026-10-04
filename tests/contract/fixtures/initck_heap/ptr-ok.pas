PROGRAM ptrok;
TYPE PR = ^R;
     R = RECORD v: INTEGER; next: PR END;
     Holder = RECORD head: PR; n: INTEGER END;
VAR g: PR;
PROCEDURE make(VAR p: PR);
BEGIN NEW(p) END;
FUNCTION same(a, b: PR): BOOLEAN;
BEGIN same := a = b END;
FUNCTION fresh: PR;
VAR t: PR;
BEGIN NEW(t); t^.v := 0; t^.next := NIL; fresh := t END;
PROCEDURE probe;
VAR p, q, u: PR; h: Holder; links: ARRAY [1..2] OF PR;
BEGIN
  {$INITCK+}
  NEW(p); q := p;
  IF same(p, q) THEN WRITELN('same');
  q := NIL;
  IF q = NIL THEN WRITELN('nil');
  p^.v := 3; p^.next := NIL;
  make(u); u^.next := p;
  h.head := fresh; h.n := 1;
  NEW(h.head^.next); h.head^.next^.next := NIL;
  links[1] := u; links[2] := links[1]^.next;
  IF links[2] = p THEN WRITELN('linked');
  {$INITCK-} g := u; {$INITCK+}
  q := u^.next;
  DISPOSE(q); DISPOSE(u); DISPOSE(h.head^.next); DISPOSE(h.head);
  WRITELN('done')
  {$INITCK-}
END;
BEGIN probe END.
