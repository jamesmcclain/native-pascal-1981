(*$INCLUDE:'convck.inc'*)
{$MATHCK-}{$NILCK-} { NVPTX boundaries; TRUNC/ROUND stay checked }
DEVICE IMPLEMENTATION OF convcku;
FUNCTION nested(r: REAL): INTEGER;
BEGIN nested := ROUND(r) END;
PROCEDURE ktrunc(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                 n: INTEGER32);
BEGIN o^[0] := TRUNC(x^[0]) END;
PROCEDURE kround(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                 n: INTEGER32);
BEGIN o^[0] := nested(x^[0]) END;
PROCEDURE kmany(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
                n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;
  IF i < n THEN
  BEGIN
    o^[2 * i] := TRUNC(x^[i]);
    o^[2 * i + 1] := ROUND(x^[i])
  END
END;
(*$INCLUDE:'convck_kinc.inc'*)
.
