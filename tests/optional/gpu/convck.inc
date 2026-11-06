DEVICE INTERFACE;
UNIT convcku (ktrunc, kround, kmany, kinc);
TYPE
  RBUF = SUPER ARRAY [0..*] OF REAL;
  IBUF = SUPER ARRAY [0..*] OF INTEGER32;
{ Every kernel takes the thread count n; ktrunc and kround ignore it. }
PROCEDURE ktrunc(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                 n: INTEGER32);
PROCEDURE kround(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                 n: INTEGER32);
PROCEDURE kmany(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                n: INTEGER32);
{ kinc (convck_kinc.inc): TRUNC a value >= 0, else ROUND it in a routine
  from convck_kround.inc. }
PROCEDURE kinc(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
               n: INTEGER32);
END;
