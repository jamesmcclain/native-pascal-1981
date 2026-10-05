(*$INCLUDE:'kh'*)
DEVICE IMPLEMENTATION OF KH;

PROCEDURE helper(b: BUF; n: INTEGER32);
BEGIN
END;

PROCEDURE writer(b: BUF);
BEGIN
  b^[0] := 1
END;

PROCEDURE scale(inp: BUF; outp: BUF; n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X + BLOCKIDX_X * BLOCKDIM_X;
  IF i < n THEN
    outp^[i] := inp^[i]
END;

PROCEDURE via_helper(inp: BUF; outp: BUF; n: INTEGER32);
VAR i: INTEGER32;
BEGIN
  i := THREADIDX_X;
  helper(inp, n)
END;

PROCEDURE via_writer(inp: BUF; n: INTEGER32);
BEGIN
  writer(inp)
END;
.
