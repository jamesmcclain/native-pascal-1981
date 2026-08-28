{ Expression and designator checking for the native type checker. }

INTERFACE;
UNIT tc_expr;
USES jsonutil, tc_base, tc_types;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
FUNCTION CheckDesignator(node: ADRMEM): INTEGER;
FUNCTION CheckExpr(node: ADRMEM): INTEGER;

END;
