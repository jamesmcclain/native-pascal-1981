PROGRAM heapforeign;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p: PR; a: ADRMEM;
BEGIN
  p := malloc(2); p^.c1 := 'f'; p^.c2 := 'g';
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); WITH p^ DO fillc(ADR c1, 2, 'z');
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); a := p; fillc(a, 2, 'y');
  {$INITCK+} WRITELN(p^.c1, p^.c2); {$INITCK-}
  NEW(p); fillc(p, 2, 'x');
  {$INITCK+} WRITELN(p^.c1, p^.c2) {$INITCK-}
END;
BEGIN probe END.
