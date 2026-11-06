{ DIALECT: vintage extended }
{ CMP-19: INPUT and OUTPUT are predeclared TEXT files (manual 13-5) that a
  program can name: EOF(INPUT), EOLN(INPUT), READ/READLN(INPUT, ...),
  WRITE/WRITELN(OUTPUT, ...) and the buffer variable INPUT^. The named
  forms and the bare READ/EOF/EOLN forms read one character stream, in
  any mix. }
PROGRAM PredeclaredFilesIo(INPUT, OUTPUT);
VAR
  x, y: INTEGER;
  c: CHAR;
  n: INTEGER;
BEGIN
  WRITELN(OUTPUT, 'start');
  IF NOT EOF(INPUT) THEN WRITELN(OUTPUT, 'not eof');
  c := INPUT^;
  WRITELN(OUTPUT, 'peek=', c, ' again=', INPUT^);
  READ(INPUT, x);
  READ(y);
  WRITE(OUTPUT, 'x=', x:1, ' y=', y:1);
  WRITELN(OUTPUT);
  IF EOLN(INPUT) = EOLN THEN WRITELN(OUTPUT, 'eoln agrees');
  READLN(INPUT);
  { A bare READ after INPUT^ sees the same character. }
  c := INPUT^;
  READ(c);
  WRITELN('bare after peek=', c);
  READLN(INPUT, x);
  WRITELN(OUTPUT, 'x2=', x:1);
  { Copy the last line through the buffer variable and GET. }
  n := 0;
  WHILE NOT EOLN(INPUT) DO
  BEGIN
    WRITE(OUTPUT, INPUT^);
    GET(INPUT);
    n := n + 1
  END;
  WRITELN(OUTPUT, ' ', n:1);
  READLN;
  IF EOF(INPUT) AND EOF THEN WRITELN(OUTPUT, 'eof')
END.
