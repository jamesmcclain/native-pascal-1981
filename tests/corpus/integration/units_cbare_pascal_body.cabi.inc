{ The [C] attribute on a routine this unit DEFINES.  units_cextern_bare
  covers the other reading of [C] -- a body that lives in libc -- and the
  difference is the point of this fixture: [C] alone chooses the SysV C
  calling convention, it does not say the body is elsewhere.  Twice is
  exported with the C convention so C callers can reach it, and esplit-style
  EXTERN is deliberately absent, so cabi's own IMPLEMENTATION owes it a
  body. }

INTERFACE;
UNIT cabi (Twice, Quad);

FUNCTION Twice(x: CINT): CINT [C];
FUNCTION Quad(x: CINT): CINT;

END;
