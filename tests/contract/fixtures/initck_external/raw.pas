PROGRAM raw;
TYPE PI = ^INTEGER; A3 = ARRAY [1..3] OF BOOLEAN;
     Cells = SUPER ARRAY [1..*] OF INTEGER; PC = ^Cells;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE poke(a: ADRMEM; v: INTEGER); EXTERN;
FUNCTION cmem: ADRMEM [C]; EXTERN;
PROCEDURE dfill(d: PC); EXTERN;
PROCEDURE dfillv(VAR d: PC); EXTERN;
PROCEDURE viaformal(VAR v: INTEGER);
VAR a: ADRMEM;
BEGIN a := ADR v; poke(a, 12); {$INITCK+} WRITELN(v) {$INITCK-} END;
PROCEDURE probe;
VAR flags: A3; x, y, i, f: INTEGER; q, p: PI; a: ADRMEM; d, g: PC;
BEGIN
  {$INITCK+}
  fillc(ADR flags, 3, CHR(1)); WRITELN(flags[1], ' ', flags[3]);
  q := ADR x; q^ := 99; WRITELN(x);
  viaformal(y); WRITELN(y);
  a := ADR i; FOR i := 1 TO 3 DO f := i; poke(a, 5); WRITELN(i + f);
  NEW(p); a := ADR p; p^ := 1; WRITELN(p^);
  NEW(d, 3); dfill(d); WRITELN(d^[1] + d^[2] + d^[3]);
  NEW(g, 2); dfillv(g); WRITELN(g^[1]);
  a := cmem; poke(a, 3); WRITELN(a = NIL)
  {$INITCK-}
END;
BEGIN probe END.
