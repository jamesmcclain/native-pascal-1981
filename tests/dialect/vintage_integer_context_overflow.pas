PROGRAM VintageIntegerContextOverflow;
CONST
  WORD_CONST = 65535;
VAR
  i: INTEGER;
  table: ARRAY[1..2] OF INTEGER;

PROCEDURE TakeInteger(n: INTEGER);
BEGIN
END;

BEGIN
  i := 32768;
  i := WORD_CONST;
  TakeInteger(32768);
  table[32768] := 1;
  FOR i := 0 TO 32768 DO
    i := i
END.
