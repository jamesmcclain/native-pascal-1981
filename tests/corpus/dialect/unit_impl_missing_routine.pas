(*$INCLUDE:'unit_impl_missing_routine.inc'*)
IMPLEMENTATION OF badunit;

FUNCTION Square(x: INTEGER): INTEGER;
BEGIN
  Square := x * x;
END;

{ Cube is declared in the INTERFACE below but never implemented here. }

BEGIN
END.
