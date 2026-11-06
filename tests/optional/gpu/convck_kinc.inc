{ Included by convck.pas: kinc's TRUNC is in this file and its ROUND in
  convck_kround.inc, so each device error names its own file. }
(*$INCLUDE:'convck_kround.inc'*)
PROCEDURE kinc(x: ADS(GLOBAL) OF RBUF; o: ADS(GLOBAL) OF IBUF;
               n: INTEGER32);
BEGIN
  IF x^[0] >= 0.0 THEN o^[0] := TRUNC(x^[0]) ELSE o^[0] := incround(x^[0])
END;
