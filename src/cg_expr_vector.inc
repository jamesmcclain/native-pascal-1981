{ Lowering for VECTOR [n] OF scalar operations: elementwise arithmetic and
  logic, VSPLAT, horizontal reductions, comparisons/masks/VSELECT, and
  VLOAD/VSTORE. Sits between cg_expr_literals and cg_expr in the codegen
  unit DAG -- it reaches downward to the type model only, and cg_expr
  dispatches into it from CodegenBinOp / CodegenUnaryOp / FuncCall.

  Empty for now (checklist step 3: wire the unit before it has contents);
  M1 onward fills it in. }

INTERFACE;
UNIT cg_expr_vector;
USES jsonutil, features, cg_base, cg_util, cg_types;

END;
