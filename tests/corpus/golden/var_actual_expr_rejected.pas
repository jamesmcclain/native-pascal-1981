{ DIALECT: vintage extended }
{ A VAR formal still needs an lvalue: only a CONST formal accepts an actual
  without storage of its own (const_actual_expr.pas). }
PROGRAM VarActualExprRejected(OUTPUT);
PROCEDURE V(VAR c: CHAR);
BEGIN
  WRITELN(c)
END;
BEGIN
  V('z')
END.
