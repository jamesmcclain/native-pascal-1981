{ DIALECT: extended }
{$RANGECK+}
{ An out-of-range initial value is checked before it is assigned: the final
  expression, evaluated after the initial one, still sees the prior value. }
PROGRAM T(output);
TYPE Digit = 1..10;
VAR i: Digit;
FUNCTION Lim: INTEGER;
BEGIN
  WRITELN('Lim sees i = ', ORD(i));
  Lim := 25;
END;
BEGIN
  i := 5;
  FOR i := 20 TO Lim DO WRITELN(i);
  WRITELN('not reached');
END.
