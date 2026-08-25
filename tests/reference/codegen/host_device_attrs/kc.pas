(*$INCLUDE:'kc'*)
DEVICE IMPLEMENTATION OF KC;
PROCEDURE copy0(inp: BUF; outp: BUF);
BEGIN
  outp^[0] := inp^[0]
END;
.
