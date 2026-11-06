{ Included by conv_incl.impl: two TRUNC sites sharing one file index. }
PROCEDURE CONV(x: ADS(GLOBAL) OF REAL; cell: ADS(GLOBAL) OF INTEGER32);
BEGIN
  cell^ := TRUNC(x^) + CROUND(x^) + TRUNC(x^ / 2.0)
END;
