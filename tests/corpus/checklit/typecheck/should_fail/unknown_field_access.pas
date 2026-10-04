{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Unknown field: z }
PROGRAM P;
TYPE
  Point = RECORD
    x, y: INTEGER
  END;
VAR p: Point;
BEGIN
  p.z := 1
END.
