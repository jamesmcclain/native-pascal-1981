{ INTERFACE exercising all three kinds of export in one unit: a TYPE, a VAR,
  and a [C] EXTERN routine whose body lives in libc rather than in cwrap's
  own IMPLEMENTATION.  The EXTERN directive spelling is the point of this
  fixture; units_cextern_bare covers the equivalent bare [C] spelling. }

INTERFACE;
UNIT cwrap (Tally, Bump, TagLen, Magnitude);

TYPE
  Tag = LSTRING(16);

VAR
  Tally: INTEGER;

FUNCTION abs(i: CINT): CINT [C]; EXTERN;

PROCEDURE Bump;
FUNCTION TagLen(t: Tag): INTEGER;
FUNCTION Magnitude(x: INTEGER32): INTEGER32;

END;
