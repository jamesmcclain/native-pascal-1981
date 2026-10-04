{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: ORD requires exactly one argument }
PROGRAM ExtendedConstIntrinsicBadArity;
CONST
  n = ORD('A', 'B');
BEGIN
END.
