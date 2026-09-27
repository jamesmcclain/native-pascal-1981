{ Expression and designator checking for the native type checker. }

INTERFACE;
UNIT tc_expr;
USES jsonutil, features, tc_base, tc_types;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
FUNCTION FoldConstInt(node: ADRMEM; VAR folded_value: INTEGER64): BOOLEAN;
VAR
  { Read immediately after CheckExpr/CheckExprForSetTarget. Recursive checks
    overwrite these channels: callers must snapshot before the next sibling. }
  last_sem_set_base, last_sem_scalar_base: INTEGER;

FUNCTION CheckExprForTarget(node: ADRMEM; target_tk: INTEGER): INTEGER;
FUNCTION CheckExprForSetTarget(node: ADRMEM; target_tk, target_set_base: INTEGER): INTEGER;
FUNCTION CheckDesignator(node: ADRMEM): INTEGER;
FUNCTION CheckExpr(node: ADRMEM): INTEGER;

END;
