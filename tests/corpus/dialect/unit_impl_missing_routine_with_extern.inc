{ The [C] EXTERN routine below is legitimately body-less, but Helper is an
  ordinary Pascal routine that the IMPLEMENTATION still fails to define.
  Exempting foreign routines from the implementation contract must not
  disable the contract for everything else declared alongside them. }

INTERFACE;
UNIT mixedunit (Helper, Magnitude);

FUNCTION abs(i: CINT): CINT [C]; EXTERN;

FUNCTION Helper(x: INTEGER): INTEGER;
FUNCTION Magnitude(x: INTEGER32): INTEGER32;

END;
