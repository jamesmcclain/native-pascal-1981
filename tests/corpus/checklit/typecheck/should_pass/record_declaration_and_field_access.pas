{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker codegen }
{ CHECK-ASSEMBLE: ir }
PROGRAM P;
TYPE
  Point = RECORD
    x, y: INTEGER
  END;
VAR p: Point;
BEGIN
  p.x := 1; p.y := 2
END.
