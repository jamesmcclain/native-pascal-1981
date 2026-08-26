(*$INCLUDE:'unit_impl_missing_routine_with_extern.inc'*)
IMPLEMENTATION OF mixedunit;

{ abs is a [C] EXTERN and correctly needs no body here.  Helper is declared
  in the INTERFACE above and is never implemented -- that must still be a
  hard error. }

FUNCTION Magnitude(x: INTEGER32): INTEGER32;
BEGIN
  Magnitude := abs(x);
END;

BEGIN
END.
