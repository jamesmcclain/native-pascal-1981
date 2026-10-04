PROGRAM files;
TYPE R = RECORD a, b: INTEGER END;
VAR g: FILE OF R;
PROCEDURE cset(VAR v: INTEGER) [C]; EXTERN;
PROCEDURE probe;
VAR f: FILE OF INTEGER; t: TEXT; x: INTEGER; c: CHAR; r: R;
BEGIN
  {$INITCK+}
  REWRITE(f); f^ := 0; PUT(f); f^ := -32768; PUT(f); cset(f^); PUT(f);
  RESET(f); x := f^; GET(f); WRITELN(x, ' ', f^, ' ', EOF(f));
  GET(f); WRITELN(f^); GET(f); WRITELN(EOF(f));
  REWRITE(g); r.a := 1; r.b := 2; g^ := r; PUT(g); RESET(g); r := g^; WRITELN(r.a + r.b);
  REWRITE(t); WRITELN(t, 'hi'); t^ := '!'; PUT(t); RESET(t);
  c := t^; WRITELN(c, EOLN(t)); READLN(t); READ(t, c); WRITELN(c); CLOSE(t)
  {$INITCK-}
END;
BEGIN probe END.
