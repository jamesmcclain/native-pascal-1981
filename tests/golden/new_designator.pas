PROGRAM new_designator(OUTPUT);
{ NEW and DISPOSE accept any pointer designator, not only a bare variable. }
{ DIALECT: extended }
TYPE PN = ^N; N = RECORD v: INTEGER; next: PN END;
     PA = ^A; A = SUPER ARRAY [1..*] OF INTEGER;
VAR q, t: PN; tbl: ARRAY [1..3] OF PN; i: INTEGER; pa: ARRAY [1..2] OF PA;
    r: RECORD p: PN END;
BEGIN
  NEW(q); q^.v := 1; NEW(q^.next); q^.next^.v := 2; NEW(q^.next^.next);
  q^.next^.next^.v := 3; q^.next^.next^.next := NIL;
  t := q; WHILE t <> NIL DO BEGIN WRITE(t^.v:2); t := t^.next END; WRITELN;
  FOR i := 1 TO 3 DO BEGIN NEW(tbl[i]); tbl[i]^.v := i * 10 END;
  WRITELN(tbl[1]^.v + tbl[2]^.v + tbl[3]^.v);
  NEW(pa[2], 4); pa[2]^[4] := 9; WRITELN(pa[2]^[4]); DISPOSE(pa[2]);
  WITH r DO BEGIN NEW(p); p^.v := 7 END; WRITELN(r.p^.v);
  DISPOSE(q^.next^.next); DISPOSE(q^.next); DISPOSE(q);
  FOR i := 1 TO 3 DO DISPOSE(tbl[i]);
END.
