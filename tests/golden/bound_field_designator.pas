{ DIALECT: extended }
PROGRAM BoundFieldDesignator(output);
TYPE
  Floats = SUPER ARRAY [2..*] OF REAL32;
  PFloats = ^Floats;
  Fixed = ARRAY [4..7] OF INTEGER;
  Holder = RECORD data: PFloats; fixed: Fixed END;
  PHolder = ^Holder;
  Root = RECORD next: PHolder END;
VAR
  p, other: PFloats;
  h: Holder;
  r: Root;
  hp: PHolder;
BEGIN
  NEW(p, 3);
  NEW(other, 9);
  h.data := p;
  WRITELN(LOWER(p^), ' ', UPPER(p^));
  WRITELN(LOWER(h.data^), ' ', UPPER(h.data^));
  h.data := other;
  WRITELN(UPPER(p^), ' ', UPPER(h.data^));
  WRITELN(LOWER(h.fixed), ' ', UPPER(h.fixed));
  NEW(hp);
  r.next := hp;
  r.next^.data := p;
  WRITELN(LOWER(r.next^.data^), ' ', UPPER(r.next^.data^));
  r.next^.data := other;
  WRITELN(UPPER(r.next^.data^));
  r.next^.data := NIL;
  WRITELN(LOWER(r.next^.data^));
  DISPOSE(hp);
  DISPOSE(other);
  DISPOSE(p)
END.
