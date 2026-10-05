PROGRAM mixedfail;
TYPE Pair = RECORD x, y: INTEGER END;
PROCEDURE consume(CONST p: Pair);
BEGIN
  {$PUSH} {$DEBUG+} {$INITCK-} WRITELN(p.x); {$POP}
  {$INITCK+} WRITELN(p.y);
  WRITELN('after')
END;
PROCEDURE relay(p: Pair);
BEGIN consume(p) END;
PROCEDURE put(VAR n: INTEGER);
BEGIN n := 7 END;
PROCEDURE probe;
VAR a, b: Pair;
BEGIN
  {$INITCK-} put(a.x); b := a;
  WRITELN('prefix'); relay(b)
END;
BEGIN probe END.
