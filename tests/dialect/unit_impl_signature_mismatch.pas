(*$INCLUDE:'unit_impl_signature_mismatch.inc'*)
IMPLEMENTATION OF badsig;

{ The INTERFACE declares Bump(x: INTEGER; step: INTEGER): INTEGER, but this
  definition drops the second parameter -- a signature mismatch. }
FUNCTION Bump(x: INTEGER): INTEGER;
BEGIN
  Bump := x + 1;
END;

BEGIN
END.
