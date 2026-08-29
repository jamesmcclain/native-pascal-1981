{ Statement traversal for the native type checker. }

INTERFACE;
UNIT tc_stmt;
USES jsonutil, features, tc_base, tc_types, tc_expr;

PROCEDURE CheckStmtList(arr: ADRMEM);
PROCEDURE CheckStmt(node: ADRMEM);

END;
