{ DIALECT: vintage extended }
{ BLT-15: niladic EOF and EOLN mean EOF(INPUT) and EOLN(INPUT) (manual
  12-10/12-11). They agree with the bare READ/READLN readers. The last
  line has no line marker; lowercase spellings name the same builtins. }
PROGRAM NiladicEofEoln(INPUT, OUTPUT);
VAR
  c: CHAR;
  lines, chars: INTEGER;
BEGIN
  lines := 0;
  chars := 0;
  WHILE NOT EOF DO
  BEGIN
    IF EOLN THEN
    BEGIN
      READLN;
      lines := lines + 1;
      WRITELN('|')
    END
    ELSE
    BEGIN
      READ(c);
      chars := chars + 1;
      WRITE(c)
    END
  END;
  WRITELN;
  WRITELN(lines:1, ' ', chars:1);
  IF eof AND Eof THEN WRITELN('still eof')
END.
