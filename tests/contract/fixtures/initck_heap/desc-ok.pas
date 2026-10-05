PROGRAM descok;
TYPE Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
     Box = RECORD n: INTEGER; cells: P END;
PROCEDURE grow(VAR d: P; n: INTEGER);
BEGIN NEW(d, n) END;
FUNCTION make(n: INTEGER): P;
VAR t: P;
BEGIN NEW(t, n); make := t END;
FUNCTION top(d: P): INTEGER64;
BEGIN top := UPPER(d^) END;
PROCEDURE probe;
VAR p, q: P; b: Box; raw: ADRMEM;
BEGIN
  {$INITCK+}
  NEW(p, 3); q := p;
  IF q = p THEN WRITELN('same ', UPPER(p^));
  grow(b.cells, 5); b.n := 1;
  WRITELN(top(b.cells), ' ', top(make(2)));
  q := NIL;
  IF q = NIL THEN WRITELN('nil');
  raw := UNSAFERAW(p);
  {$INITCK-} q := UNSAFESUPER(P, raw, 1, 2); {$INITCK+}
  WRITELN(UPPER(q^));
  DISPOSE(p); DISPOSE(b.cells)
  {$INITCK-}
END;
BEGIN probe END.
