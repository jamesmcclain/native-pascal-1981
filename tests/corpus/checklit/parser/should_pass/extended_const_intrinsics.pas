{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
PROGRAM ExtendedConstIntrinsics;
CONST
  c = CHR(SUCC(ORD('A')));
  n = PRED(ORD(c));
BEGIN
END.
