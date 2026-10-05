(*$INCLUDE:'unit_impl_missing_var.inc'*)
IMPLEMENTATION OF badvar;

{ Counter is declared as an exported VAR in the INTERFACE below but never
  given its own storage here. }
PROCEDURE Bump;
BEGIN
END;

BEGIN
END.
