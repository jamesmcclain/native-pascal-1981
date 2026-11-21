{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-47: $RANGECK guards length-byte stores through ^LSTRING's .LEN and
  index zero against min(UPPER(p^), 255). }
PROGRAM SuperStringPointerLengthRangeckBad(OUTPUT);
VAR
  p: ^LSTRING;
BEGIN
  NEW(p, 3);
  p^.LEN := CHR(3);
  WRITELN('length ', ORD(p^.LEN), ' of ', UPPER(p^));
  p^.LEN := CHR(4);
  WRITELN('not reached');
  DISPOSE(p);
END.
