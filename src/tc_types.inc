{ AST type-expression resolution for the native type checker. }

INTERFACE;
UNIT tc_types;
USES jsonutil, features, tc_base;

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
FUNCTION IsSuperTypeExpr(node: ADRMEM): BOOLEAN;

END;
