{ DIALECT: vintage extended }
{ CMP-19: the predeclared INPUT and OUTPUT are TEXT variables, so they
  can be VAR TEXT actuals. The routine reads INPUT through its formal;
  the main program then goes on with the bare READ on the same stream.
  The heading names neither file. }
PROGRAM PredeclaredFilesActual;
VAR
  n, rest: INTEGER;

PROCEDURE CountWord(VAR f: TEXT; VAR count: INTEGER);
BEGIN
  count := 0;
  WHILE f^ <> ' ' DO
  BEGIN
    GET(f);
    count := count + 1
  END
END;

PROCEDURE Say(VAR f: TEXT; n: INTEGER);
BEGIN
  WRITELN(f, 'count ', n:1)
END;

BEGIN
  CountWord(INPUT, n);
  Say(OUTPUT, n);
  READ(rest);
  WRITELN('rest ', rest:1);
  READLN;
  IF EOF(INPUT) THEN WRITELN(OUTPUT, 'done')
END.
