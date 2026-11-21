{ DIALECT: extended }
{ NEW-36: IBM manual 5-9..5-10 constant expression examples using ORD/CHR/
  SUCC/PRED (extended-const-intrinsics) and `*` string concatenation with
  CHR(...). }
PROGRAM ConstExprExtendedChr(OUTPUT);
CONST
  MANUAL_NUM = (100 + ORD('X')) * 8#100 + ORD('Y');
  HEADER = 'Now''s the time';
  POLITC = HEADER * CHR(32) * 'For all good men';
  EDGE = SUCC('A') * PRED('Z');
VAR
  s: LSTRING(40);
BEGIN
  WRITELN(MANUAL_NUM);
  WRITELN(POLITC);
  s := EDGE;
  WRITELN(s, ' ', ORD(s[0]));
END.
