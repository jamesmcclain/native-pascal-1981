{ RETURN, BREAK and CYCLE; FOR TO and DOWNTO. A FOR limit is evaluated
  once, the control variable ends one past it, and a limit at the type's
  maximum ends the loop (the native compiler would wrap and loop forever). }
(*$INCLUDE:'testio.inc'*)
PROGRAM control(input, output);
USES testio;

VAR
  i, limit: INTEGER;
  w: INTEGER32;

FUNCTION FirstOver(n: INTEGER): INTEGER;
VAR
  k: INTEGER;
BEGIN
  FirstOver := -1;
  FOR k := 1 TO 100 DO
    IF k * k > n THEN
    BEGIN
      FirstOver := k;
      RETURN;
    END;
END;

PROCEDURE Early(flag: BOOLEAN);
BEGIN
  IF flag THEN
    RETURN;
  WRITE('not returned');
  WRITELN;
END;

BEGIN
  WriteLabel('odd numbers below 10, stopping at 7');
  FOR i := 1 TO 10 DO
  BEGIN
    IF i MOD 2 = 0 THEN
      CYCLE;
    IF i > 7 THEN
      BREAK;
    WriteInt(i);
    WRITE(' ');
  END;
  WRITELN;
  WriteLabel('DOWNTO');
  FOR i := 5 DOWNTO 1 DO
    WriteInt(i);
  WRITELN;
  WriteLabel('FirstOver(50)');
  WriteInt(FirstOver(50));
  WRITELN;
  Early(TRUE);
  Early(FALSE);
  limit := 3;
  w := 0;
  FOR i := 1 TO limit DO
  BEGIN
    w := w + 1;
    IF i = 2 THEN
      limit := 6;
  END;
  WriteLabel('iterations with the limit raised to 6');
  WriteInt(w);
  WRITELN;
  FOR i := 1 TO 4 DO
    w := i;
  WriteLabel('control variable after FOR 1 TO 4');
  WriteInt(i);
  WRITELN;
  w := 0;
  FOR i := 32760 TO 32767 DO
    w := w + 1;
  WriteLabel('iterations of FOR 32760 TO 32767');
  WriteInt(w);
  WRITELN;
  i := 0;
  WHILE i < 100 DO
  BEGIN
    i := i + 1;
    IF i < 50 THEN
      CYCLE;
    BREAK;
  END;
  WriteLabel('WHILE with CYCLE and BREAK');
  WriteInt(i);
  WRITELN;
END.
