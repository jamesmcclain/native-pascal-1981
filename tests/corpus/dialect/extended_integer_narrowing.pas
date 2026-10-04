{ DIALECT: extended }
PROGRAM ExtendedIntegerNarrowing;
VAR
  narrow_i: INTEGER;
  narrow_w: WORD;
  wide_i: INTEGER32;
  wide_w: WORD32;

PROCEDURE TakeInteger(n: INTEGER);
BEGIN
END;

BEGIN
  narrow_i := wide_i;
  narrow_w := wide_w;
  TakeInteger(wide_i)
END.
