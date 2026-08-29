{ AST type-expression resolution for the native type checker. }

INTERFACE;
UNIT tc_types;
USES jsonutil, features, tc_base;

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, idx_tk: INTEGER);

END;
