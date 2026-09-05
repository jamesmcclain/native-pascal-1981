PROGRAM NestedBuiltinShadowScope(output);
{ A nested FUNCTION SQRT shadows the builtin only inside its parent. The
  outer-level call must reach the builtin again once A's scope has ended --
  codegen's routine table is trimmed by PopScope so it agrees with the
  typechecker, which resolved the outer call to the builtin. }
VAR r: REAL;

PROCEDURE A;
VAR t: REAL;

  FUNCTION SQRT(x, y: REAL): REAL;
  BEGIN
    SQRT := x * y;
  END;

BEGIN
  t := SQRT(4.0, 2.0);
  WRITELN(t:6:2);
END;

BEGIN
  A;
  r := SQRT(4.0);
  WRITELN(r:6:2);
END.
