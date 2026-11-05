{$INITCK+}
{ The final expression is evaluated before the control variable is
  assigned, so naming an unset control variable there is an uninitialized
  read rather than a read of the initial value. }
PROGRAM T(output);
PROCEDURE P;
VAR i, n: INTEGER;
BEGIN
  n := 0;
  FOR i := 1 TO i DO n := n + 1;
  WRITELN(n);
END;
BEGIN
  P;
END.
