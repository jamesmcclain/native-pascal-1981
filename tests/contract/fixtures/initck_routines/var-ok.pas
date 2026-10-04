PROGRAM varok;
VAR g: INTEGER;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
{$INITCK+}
PROCEDURE setit(VAR n: INTEGER; k: INTEGER); BEGIN n := k END;
PROCEDURE bump(VAR n: INTEGER); BEGIN n := n + 1 END;
PROCEDURE fwd(VAR n: INTEGER); BEGIN setit(n, -32768) END;
PROCEDURE copyit(VAR dst: INTEGER; CONST src: INTEGER); BEGIN dst := src END;
PROCEDURE swap(VAR a, b: INTEGER); VAR t: INTEGER; BEGIN t := a; a := b; b := t END;
PROCEDURE flags(VAR b: BOOLEAN; VAR c: CHAR); BEGIN b := NOT b; c := 'z' END;
PROCEDURE third(a, b: INTEGER; c: CHAR); BEGIN WRITELN(a + b, c) END;
PROCEDURE show(CONST c: INTEGER); BEGIN WRITELN(c) END;
{$INITCK-}
PROCEDURE zap(VAR n: INTEGER); BEGIN fillc(ADR n, 2, CHR(0)) END;
{$INITCK+}
PROCEDURE probe;
VAR x, y, u: INTEGER; b: BOOLEAN; c, w: CHAR;
BEGIN
  setit(x, 1); bump(x); fwd(y); WRITELN(x, ' ', y);
  copyit(u, x); swap(u, y); WRITELN(u, ' ', y);
  swap(x, x); bump(x); WRITELN(x);
  b := FALSE; flags(b, c); WRITELN(ORD(b), c);
  g := 7; bump(g); show(g); setit(g, 1); bump(g); show(g);
  zap(x); WRITELN(x);
  {$INITCK-} fillc(ADR g, 2, w); {$INITCK+} third(1, 2, 'A')
END;
BEGIN probe END.
{$INITCK-}
