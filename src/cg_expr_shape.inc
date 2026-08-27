{ Type-only expression-shape queries.  This unit is deliberately below the
  expression dispatcher: its routines inspect AST and symbol/type state but
  emit no IR and do not evaluate expressions. }

INTERFACE;
UNIT cg_expr_shape;
USES jsonutil, cg_base, cg_util, cg_types, cg_symbols;

FUNCTION StaticDesignatorType(node: ADRMEM): INTEGER;
FUNCTION IsStringShapedExpr(node: ADRMEM): BOOLEAN;

END;
