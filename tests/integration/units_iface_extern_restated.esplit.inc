{ The other half of the split-implementation shape units_vintage_extern
  covers: there the INTERFACE declares Helper plainly and only the
  IMPLEMENTATION marks it EXTERN, here the INTERFACE itself carries the
  EXTERN directive and the IMPLEMENTATION re-states it -- which the manual's
  Units chapter allows, an implementation "must declare those not
  implemented with the EXTERN directive at the start of the implementation"
  whether or not the interface already said so.

  The re-statement is the point of this fixture: it is a body-less
  redeclaration of a name already known to be EXTERN, the one shape the
  "EXTERN routine cannot be defined here" rule must NOT reject. }

INTERFACE;
UNIT esplit (Helper, Local);

FUNCTION Helper(x: INTEGER32): INTEGER32; EXTERN;
FUNCTION Local(x: INTEGER32): INTEGER32;

END;
