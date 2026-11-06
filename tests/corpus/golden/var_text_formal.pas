{ DIALECT: vintage extended }
PROGRAM VarTextFormal(OUTPUT);
{ TEXT is one predeclared type: a VAR formal written as plain TEXT takes a
  TEXT actual, an actual of an alias of TEXT, and another TEXT formal, and
  an alias formal takes a plain TEXT actual. The routine does real I/O
  through its formal on the caller's scratch file. A typed file passes
  through a VAR formal of its own named type. }
TYPE
  Txt = TEXT;
  IntF = FILE OF INTEGER;
VAR
  f: TEXT;
  g: Txt;
  h: IntF;
PROCEDURE Plain(VAR t: TEXT);
BEGIN
  WRITELN('plain')
END;
PROCEDURE Aliased(VAR t: Txt);
BEGIN
  WRITELN('aliased')
END;
PROCEDURE Emit(VAR u: TEXT; n: INTEGER);
BEGIN
  WRITELN(u, 'line ', n)
END;
PROCEDURE RoundTrip(VAR t: TEXT);
VAR
  s: LSTRING(20);
  n: INTEGER;
BEGIN
  REWRITE(t);
  Emit(t, 1);
  WRITELN(t, 42);
  RESET(t);
  READLN(t, s);
  READLN(t, n);
  WRITELN(s, ' / ', n + 1, ' eof=', EOF(t));
  CLOSE(t)
END;
PROCEDURE Numbers(VAR t: IntF);
VAR
  x: INTEGER;
BEGIN
  REWRITE(t);
  t^ := 7;
  PUT(t);
  RESET(t);
  x := t^;
  WRITELN('typed ', x);
  CLOSE(t)
END;
BEGIN
  Plain(f);
  Plain(g);
  Aliased(f);
  Aliased(g);
  RoundTrip(f);
  RoundTrip(g);
  Numbers(h)
END.
