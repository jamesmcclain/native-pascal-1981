{ The 1981 manual's split-implementation shape: one INTERFACE implemented
  partly in Pascal and partly in foreign code.  Per the Units chapter, "any
  implementation section that does not implement all interface procedures and
  functions must declare those not implemented with the EXTERN directive at
  the start of the implementation" -- so Helper below is declared, not
  defined, in vsplit's own IMPLEMENTATION, and supplied by C instead. }

INTERFACE;
UNIT vsplit (Helper, Local);

FUNCTION Helper(x: INTEGER32): INTEGER32;
FUNCTION Local(x: INTEGER32): INTEGER32;

END;
