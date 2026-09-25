{ A parameterless function named without an argument list has its result
  type to the typechecker, so storing a SET result in an INTEGER is a
  typecheck error rather than a codegen one. }
PROGRAM BareFunctionAssignType(output);
TYPE BoolSet = SET OF BOOLEAN;
VAR bs: BoolSet; i: INTEGER;
FUNCTION getb: BoolSet; BEGIN getb := bs END;
BEGIN i := getb END.
