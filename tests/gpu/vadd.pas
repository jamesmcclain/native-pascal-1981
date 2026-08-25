(*$INCLUDE:'vadd.inc'*)
DEVICE IMPLEMENTATION OF vaddu;
PROCEDURE add(a: ADS(GLOBAL) OF BUFFER; b: ADS(GLOBAL) OF BUFFER;
              c: ADS(GLOBAL) OF BUFFER; n: INTEGER32);
VAR
  i, stride: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;
  stride := BLOCKDIM_X * GRIDDIM_X;
  WHILE i < n DO
  BEGIN
    c^[i] := a^[i] + b^[i];
    i := i + stride
  END
END;
.
