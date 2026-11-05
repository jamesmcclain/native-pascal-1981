{ The initial value is evaluated first, then the final value, both before
  the FOR statement assigns its control variable (manual 9-17): a final
  expression naming the control variable reads its prior value. }
PROGRAM T(output);
VAR i, n: INTEGER;
FUNCTION Lim: INTEGER;
BEGIN
  WRITELN('Lim sees i = ', i);
  Lim := i + 1;
END;
BEGIN
  i := 100;
  n := 0;
  FOR i := 1 TO i + 2 DO n := n + 1;
  WRITELN('TO ', n);
  i := 3;
  n := 0;
  FOR i := 50 DOWNTO i DO n := n + 1;
  WRITELN('DOWNTO ', n);
  i := 7;
  FOR i := 1 TO Lim DO WRITE(i:3);
  WRITELN;
END.
