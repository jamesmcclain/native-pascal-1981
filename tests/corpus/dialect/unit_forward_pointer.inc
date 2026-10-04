INTERFACE;
UNIT fwdlist (PN, N, Count);

TYPE
  PN = ^N;
  N = RECORD v: INTEGER; nx: PN END;

FUNCTION Count(p: PN): INTEGER;

END;
