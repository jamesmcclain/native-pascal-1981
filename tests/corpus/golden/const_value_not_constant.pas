{ DIALECT: vintage extended }
{ A CONST value is a constant expression (IBM manual 5-9). A variable,
  parameter or function name in it, signed or as a WRD/BYWORD argument,
  is a located type error. It used to reach codegen, which aborted with
  "IntLiteralValue: not a foldable integer constant". }
PROGRAM const_value_not_constant(OUTPUT);
VAR g: INTEGER;
FUNCTION f: INTEGER; BEGIN f := 1 END;
PROCEDURE p(q: INTEGER);
CONST
  A = q;
  B = -g;
  C = f;
  D = WRD(q);
  E = BYWORD(g, 1);
BEGIN WRITELN(A, B, C, D, E) END;
BEGIN p(1) END.
