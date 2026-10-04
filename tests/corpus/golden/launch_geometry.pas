{ DIALECT: extended }
{ LAUNCH runs its kernel once per thread in both geometry forms: a
  (grid, block) pair, 2 x 3 = 6 threads adding 1, and the six-value form,
  a 1x1x1 grid of 2x1x3 blocks = 6 threads adding 10. }
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
