{ DIALECT: extended }
PROGRAM superok;
TYPE Cells = SUPER ARRAY [-1..*] OF INTEGER;
     P = ^Cells;
     R = RECORD a: CHAR; ok: BOOLEAN END;
     Rs = SUPER ARRAY [1..*] OF R;
     PR = ^Rs;
     Node = RECORD v: INTEGER END;
     PN = ^Node;
     Links = SUPER ARRAY [0..*] OF PN;
     PL = ^Links;
     V4 = VECTOR [4] OF INTEGER;
PROCEDURE swap(VAR x, y: INTEGER);
VAR t: INTEGER;
BEGIN t := x; x := y; y := t END;
PROCEDURE fill(d: P; v: INTEGER);
VAR i: INTEGER;
BEGIN FOR i := -1 TO RETYPE(INTEGER, UPPER(d^)) DO d^[i] := v + i END;
FUNCTION make(n: INTEGER): PR;
VAR t: PR;
BEGIN NEW(t, n); make := t END;
PROCEDURE probe(k: INTEGER);
VAR p, q: P; r: PR; l: PL; n: PN; i: INTEGER;
BEGIN
  {$INITCK+}
  NEW(p, 3); p^[-1] := -32768; p^[0] := 0;
  FOR i := 1 TO 3 DO p^[i] := i * k;
  q := p; swap(q^[1], q^[3]);
  WRITELN(p^[-1], ' ', p^[0], ' ', p^[1], ' ', q^[3]);
  fill(p, 10); WRITELN(p^[2]);
  r := make(2); r^[2].a := 'x'; r^[2].ok := FALSE;
  WITH r^[1] DO BEGIN a := 'y'; ok := TRUE END;
  WRITELN(r^[1].a, r^[2].a, ORD(r^[1].ok), ORD(r^[2].ok));
  NEW(l, 1); NEW(l^[0]); n := l^[0]; n^.v := 7; l^[1] := l^[0];
  n := l^[1]; WRITELN(n^.v);
  { VSTORE writes elements through a path INITCK does not model: the
    allocation is released and reads as initialized afterwards. }
  NEW(p, 2); {$INITCK-} VSTORE(p^, -1, VSPLAT(4, V4)); {$INITCK+} WRITELN(p^[2]);
  DISPOSE(p); DISPOSE(r); DISPOSE(n); DISPOSE(l)
  {$INITCK-}
END;
BEGIN probe(1); probe(2) END.
