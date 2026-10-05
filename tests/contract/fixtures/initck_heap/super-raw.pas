{ DIALECT: extended }
PROGRAM superraw;
TYPE Chars = SUPER ARRAY [1..*] OF CHAR;
     P = ^Chars;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p, q: P; raw: ADRMEM;
BEGIN
  NEW(p, 2); fillc(UNSAFERAW(p), 2, 'z');
  {$INITCK+} WRITELN(p^[1], p^[2]); {$INITCK-}
  raw := malloc(2); fillc(raw, 2, 'm'); q := UNSAFESUPER(P, raw, 1, 2);
  {$INITCK+} WRITELN(q^[1], q^[2]) {$INITCK-}
END;
BEGIN probe END.
