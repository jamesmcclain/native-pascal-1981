{ DIALECT: extended }
{ UPPER of a SET OF BOOLEAN union is a BOOLEAN in the typechecker too, as
  it is in codegen, so storing it in an INTEGER is rejected. }
PROGRAM SetExpressionBoundType(output);
TYPE BoolSet = SET OF BOOLEAN;
VAR bs: BoolSet; i: INTEGER;
BEGIN
  i := UPPER(bs + bs)
END.
