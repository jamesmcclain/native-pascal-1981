{ Expression and designator checking for the native type checker. }

INTERFACE;
UNIT tc_expr;
USES jsonutil, features, tc_base, tc_types;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
FUNCTION FoldConstInt(node: ADRMEM; VAR folded_value: INTEGER64): BOOLEAN;
FUNCTION CheckExprForTarget(node: ADRMEM; target_tk: INTEGER): INTEGER;
FUNCTION CheckDesignator(node: ADRMEM): INTEGER;
FUNCTION CheckExpr(node: ADRMEM): INTEGER;

END;
