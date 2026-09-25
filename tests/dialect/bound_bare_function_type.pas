{ DIALECT: extended }
{ UPPER of a bare SET OF BOOLEAN function is a BOOLEAN to the typechecker
  as well as to codegen, so storing it in an INTEGER is rejected. }
PROGRAM BoundBareFunctionType(output);
TYPE BoolSet = SET OF BOOLEAN;
VAR bs: BoolSet; i: INTEGER;
FUNCTION getb: BoolSet; BEGIN getb := bs END;
BEGIN i := UPPER(getb) END.
