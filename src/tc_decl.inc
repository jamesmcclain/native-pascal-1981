{ Declaration, interface, and compilation-unit checking. }

INTERFACE;
UNIT tc_decl;
USES jsonutil, features, tc_base, tc_types, tc_expr, tc_stmt;

PROCEDURE CheckRoot(root: ADRMEM);

END;
