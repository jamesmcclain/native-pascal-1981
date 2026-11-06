{ DIALECT: extended }
{ NEW-6: an intrinsic argument checked outside the assignment's context
  still has to be of a type the intrinsic takes: a literal that needs
  INTEGER32, an INTEGER32 variable and a CHAR are not HIBYTE/LOBYTE
  arguments, and a constant result must still fit its target. }
PROGRAM ExtendedIntrinsicArgumentErrors;
VAR
  x: INTEGER32;
  i: INTEGER;
  c: CHAR;
BEGIN
  x := HIBYTE(70000);
  x := LOBYTE(x);
  i := HIBYTE(c);
  i := ABS(70000);
  x := ABS(TRUE);
  i := ORD(70000)
END.
