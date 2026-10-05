PROGRAM reuse;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p, q, old: PR; a: ADRMEM;
BEGIN
  NEW(p); p^.c1 := 'a'; old := p; DISPOSE(p);
  a := malloc(2); fillc(a, 2, 'm'); q := a;
  IF q = old THEN WRITELN('reused') ELSE WRITELN('fresh');
  {$INITCK+} WRITELN(q^.c1, q^.c2) {$INITCK-}
END;
BEGIN probe END.
