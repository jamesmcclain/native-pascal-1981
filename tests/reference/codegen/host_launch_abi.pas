PROGRAM main(output);
TYPE
  PINT = ^INTEGER32;
VAR
  p: PINT;

PROCEDURE bump(q: PINT; step: INTEGER32);
BEGIN
  q^ := q^ + step
END;

BEGIN
  NEW(p);
  p^ := 0;
  LAUNCH(bump, 2, 3, p, 1);
  WRITELN(p^);
  LAUNCH(bump, 1, 1, 1, 2, 1, 3, p, 10);
  WRITELN(p^);
  DISPOSE(p)
END.
