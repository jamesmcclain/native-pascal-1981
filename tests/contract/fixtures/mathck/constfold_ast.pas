{ The CONST/CASE/bound grammar admits no binary expression, so the suite
  replaces N's value in this program's parsed AST with -7 DIV or MOD 2 or 0
  and feeds it to the typechecker and to codegen separately. }
PROGRAM ASTProbe; CONST N = -3; TYPE A = ARRAY [N..0] OF INTEGER; VAR x: A; k: INTEGER; BEGIN x[N] := 9; k := N; CASE k OF N: WRITELN(x[N]) END END.
