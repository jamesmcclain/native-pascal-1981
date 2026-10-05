PROGRAM forok;
PROCEDURE probe;
LABEL 9;
VAR i, s: INTEGER; c: CHAR; b: BOOLEAN;
BEGIN
  {$INITCK+}
  s := 0;
  FOR i := 1 TO 3 DO s := s + i;
  FOR i := 3 DOWNTO 1 DO s := s + i;
  WRITELN(s);
  FOR i := 1 TO 10 DO IF i = 4 THEN BREAK;
  WRITELN(i);
  FOR i := 1 TO 10 DO IF i = 6 THEN GOTO 9;
  9: WRITELN(i);
  FOR c := 'x' TO 'z' DO WRITE(c);
  FOR b := FALSE TO TRUE DO WRITE(ORD(b));
  WRITELN;
  FOR i := 1 TO 0 DO WRITELN('never');
  i := -32768; WRITELN(i)
  {$INITCK-}
END;
BEGIN probe END.
