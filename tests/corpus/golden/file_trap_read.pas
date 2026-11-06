{ DIALECT: vintage extended }
{ OPT: 0 2 }
PROGRAM FileTrapRead(OUTPUT);
{ Trapped I/O from source (F.TRAP, F.ERRS; manual 12-32..12-33). With
  F.TRAP set, a malformed INTEGER, BOOLEAN or enumeration READ sets
  F.ERRS to 14 instead of aborting and leaves its destination unchanged;
  clearing F.ERRS lets the program continue. A typed file traps a PUT in
  read mode (2) and a GET past its end (3). }
TYPE
  Colour = (RED, GREEN, BLUE);
  Txt = TEXT; { a VAR formal needs the actual's named file type }
VAR
  f: Txt;
  g: FILE OF INTEGER;
  i, x: INTEGER;
  b: BOOLEAN;
  c: Colour;
  w: WORD;
PROCEDURE Show(VAR t: Txt);
{ The fields of a VAR formal are the actual's own FCB fields. }
BEGIN
  WRITELN('errs=', t.ERRS, ' trap=', t.TRAP)
END;
PROCEDURE Clear(VAR e: WORD);
BEGIN
  e := 0
END;
BEGIN
  REWRITE(f);
  WRITELN(f, 'x12');
  WRITELN(f, '*TRUE');
  WRITELN(f, 'PURPLE');
  WRITELN(f, '42 2'); { by ordinal: vintage has no symbolic enum READ }
  RESET(f);
  Show(f);
  f.TRAP := TRUE;
  Show(f);
  i := 7;
  READ(f, i);
  WRITELN('int errs=', f.ERRS, ' i=', i);
  IF f.ERRS <> 0 THEN f.ERRS := 0;
  READLN(f);
  b := TRUE;
  READ(f, b);
  w := f.ERRS;
  WRITELN('bool errs=', w, ' b=', b);
  Clear(f.ERRS);
  READLN(f);
  c := GREEN;
  READ(f, c);
  WRITELN('enum errs=', f.ERRS, ' kept=', c = GREEN);
  f.ERRS := 0;
  READLN(f);
  READ(f, i, c);
  WRITELN('good errs=', f.ERRS, ' i=', i, ' blue=', c = BLUE);
  f.TRAP := FALSE;
  Show(f);
  CLOSE(f);

  REWRITE(g);
  g^ := 5;
  PUT(g);
  RESET(g);
  g.TRAP := TRUE;
  PUT(g);
  WRITELN('put errs=', g.ERRS);
  g.ERRS := 0;
  x := g^;
  GET(g);
  GET(g);
  WRITELN('get errs=', g.ERRS, ' x=', x, ' eof=', EOF(g));
  g.ERRS := 0;
  WRITELN('cleared=', g.ERRS = 0, ' trap=', g.TRAP);
  CLOSE(g)
END.
